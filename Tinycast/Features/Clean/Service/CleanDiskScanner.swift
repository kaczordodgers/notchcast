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
                nodes[index].unreadable = opened.listing.entryErrors > 0
                for entry in opened.listing.entries {
                    try Task.checkCancellation()
                    let isDirectory = entry.kind == .directory
                    let key = "\(entry.device):\(entry.inode)"
                    let unique = seen.insert(key).inserted
                    let child = nodes.count
                    nodes.append(CleanDiskScan.Node(
                        path: nodes[index].path.appendingPathComponent(entry.name),
                        parent: index, directory: isDirectory, device: entry.device,
                        inode: entry.inode, allocatedSize: unique ? entry.allocatedSize : 0))
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
            if let parent = nodes[index].parent {
                nodes[parent].allocatedSize += nodes[index].allocatedSize
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
}
