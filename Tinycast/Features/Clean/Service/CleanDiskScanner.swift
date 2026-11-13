import CryptoKit
import Darwin
import Foundation

struct CleanDiskScanner: Sendable {
    struct Limits: Sendable {
        var nodes = 100_000
        var largestFiles = 100
    }

    enum Failure: Error { case refused, changed, staleScan, outsideRoot }

    let root: URL
    let limits: Limits
    let crossVolumes: Bool
    let now: @Sendable () -> Date
    let transport: any CleanTrashTransport

    @concurrent func scan(
        id: UUID,
        progress: @Sendable (UUID, Int) -> Void = { _, _ in },
        isCurrent: @Sendable (UUID) -> Bool = { _ in true }
    ) async throws -> CleanDiskScan {
        try Task.checkCancellation()
        guard let previous = CleanDiskDirectoryReader.refuseCloudDownloadsOnThisThread()
        else { throw Failure.refused }
        defer { CleanDiskDirectoryReader.restoreCloudDownloadsOnThisThread(previous) }
        let directory = try CleanDiskDirectoryReader.directory(root.path).get()
        let physicalRoot = URL(fileURLWithPath: directory.path)
        guard limits.nodes > 0 else { throw Failure.refused }
        var rootInfo = stat()
        guard lstat(physicalRoot.path, &rootInfo) == 0 else { throw Failure.changed }
        var nodes = [CleanDiskScan.Node(
            path: physicalRoot, parent: nil, directory: true, device: directory.device,
            inode: UInt64(rootInfo.st_ino), allocatedSize: directory.ownAllocation)]
        var pending = [0]
        nodes[0].subtreeFingerprint = fingerprint(rootInfo)
        var seen: Set<String> = ["\(directory.device):\(rootInfo.st_ino)"]
        var regularFiles = [Int]()
        var limited = false
        while let index = pending.popLast() {
            try Task.checkCancellation()
            guard isCurrent(id) else { throw CancellationError() }
            let result = CleanDiskDirectoryReader.list(
                nodes[index].path.path, device: nodes[index].device,
                limit: max(0, limits.nodes - nodes.count), stop: { Task.isCancelled })
            try Task.checkCancellation()
            switch result {
            case .failure(let failure):
                nodes[index].unreadable = true
                if failure == .system(EOVERFLOW) { limited = true }
            case .success(let opened):
                nodes[index].unreadable = nodes[index].unreadable || opened.listing.entryErrors > 0
                for entry in opened.listing.entries.sorted(by: { $0.name < $1.name }) {
                    try Task.checkCancellation()
                    let isDirectory = entry.kind == .directory
                    let key = "\(entry.device):\(entry.inode)"
                    let unique = seen.insert(key).inserted
                    let child = nodes.count
                    nodes.append(CleanDiskScan.Node(
                        path: nodes[index].path.appendingPathComponent(entry.name),
                        parent: index, directory: isDirectory, device: entry.device,
                        inode: entry.inode, allocatedSize: unique ? entry.allocatedSize : 0))
                    if entry.kind != .file && entry.kind != .directory { nodes[child].unreadable = true }
                    var info = stat()
                    if lstat(nodes[child].path.path, &info) == 0,
                       UInt64(info.st_ino) == entry.inode,
                       UInt64(UInt32(bitPattern: info.st_dev)) == entry.device {
                        nodes[child].subtreeFingerprint = fingerprint(info)
                    } else {
                        nodes[child].unreadable = true
                    }
                    if isDirectory && !unique { nodes[child].unreadable = true }
                    if entry.kind == .file { regularFiles.append(child) }
                    if isDirectory && unique {
                        if entry.isDataless || (!crossVolumes && entry.device != directory.device) {
                            nodes[child].unreadable = true
                        } else {
                            pending.append(child)
                        }
                    }
                }
            }
            progress(id, nodes.count)
        }
        for index in nodes.indices.reversed() {
            nodes[index].subtreeFingerprint = Data(SHA256.hash(data: nodes[index].subtreeFingerprint))
            if let parent = nodes[index].parent {
                nodes[parent].allocatedSize += nodes[index].allocatedSize
                nodes[parent].unreadable = nodes[parent].unreadable || nodes[index].unreadable
                let name = Data(nodes[index].path.lastPathComponent.utf8)
                nodes[parent].subtreeFingerprint.append(Data(SHA256.hash(data: name)))
                nodes[parent].subtreeFingerprint.append(nodes[index].subtreeFingerprint)
            }
        }
        let largest = regularFiles
            .sorted { nodes[$0].allocatedSize > nodes[$1].allocatedSize }
            .prefix(max(0, limits.largestFiles))
        try Task.checkCancellation()
        guard isCurrent(id) else { throw CancellationError() }
        return CleanDiskScan(id: id, root: physicalRoot, capturedAt: now(),
                             nodes: nodes, largestFiles: Array(largest), limited: limited)
    }

    @concurrent func trash(_ index: Int, from scan: CleanDiskScan, currentID: UUID) async throws {
        try Task.checkCancellation()
        let currentRoot = try CleanDiskDirectoryReader.directory(root.path).get()
        guard scan.id == currentID, scan.nodes.indices.contains(index), index != 0,
              scan.root.path == currentRoot.path else { throw Failure.staleScan }
        let item = scan.nodes[index]
        guard !item.unreadable else { throw Failure.changed }
        if item.directory {
            let scanner = CleanDiskScanner(root: item.path, limits: limits,
                                           crossVolumes: crossVolumes, now: now, transport: transport)
            let current = try await scanner.scan(id: currentID)
            guard !current.nodes[0].unreadable,
                  current.nodes[0].subtreeFingerprint == item.subtreeFingerprint
            else { throw Failure.changed }
        }
        var rootInfo = stat()
        guard lstat(scan.root.path, &rootInfo) == 0,
              UInt64(rootInfo.st_ino) == scan.nodes[0].inode,
              UInt64(UInt32(bitPattern: rootInfo.st_dev)) == scan.nodes[0].device
        else { throw Failure.changed }
        guard item.path.path.hasPrefix(scan.root.path + "/"),
              !item.path.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else { throw Failure.outsideRoot }
        let parent = item.path.deletingLastPathComponent()
        _ = try CleanDiskDirectoryReader.directory(parent.path).get()
        var info = stat()
        guard lstat(item.path.path, &info) == 0,
              info.st_mode & S_IFMT != S_IFLNK,
              UInt64(UInt32(bitPattern: info.st_dev)) == item.device,
              UInt64(info.st_ino) == item.inode else { throw Failure.changed }
        try Task.checkCancellation()
        try transport.trash(item.path)
    }

    private func fingerprint(_ info: stat) -> Data {
        let values = [
            String(info.st_dev), String(info.st_ino), String(info.st_mode), String(info.st_size),
            String(info.st_mtimespec.tv_sec), String(info.st_mtimespec.tv_nsec),
            String(info.st_ctimespec.tv_sec), String(info.st_ctimespec.tv_nsec)
        ]
        return Data(values.joined(separator: ":").utf8)
    }
}
