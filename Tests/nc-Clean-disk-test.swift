import Darwin
import Foundation
import Synchronization

final class FakeDiskTrash: CleanTrashTransport {
    let calls = Mutex<[URL]>([])

    func trash(_ url: URL) throws {
        calls.withLock { $0.append(url) }
    }
}

@main
struct CleanDiskTest {
    static func main() async throws {
        let manager = FileManager()
        let resolved = realpath(manager.temporaryDirectory.path, nil)!
        defer { free(resolved) }
        let sandbox = URL(fileURLWithPath: String(cString: resolved))
            .appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("root")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("data")
        try Data(repeating: 7, count: 16_384).write(to: file)
        let alias = root.appendingPathComponent("hard")
        precondition(link(file.path, alias.path) == 0)
        let sparse = root.appendingPathComponent("sparse")
        let descriptor = open(sparse.path, O_CREAT | O_WRONLY, 0o600)
        precondition(descriptor >= 0)
        precondition(ftruncate(descriptor, 32 * 1024 * 1024) == 0)
        close(descriptor)
        let sentinel = sandbox.appendingPathComponent("sentinel")
        try Data([1]).write(to: sentinel)
        try manager.createSymbolicLink(at: root.appendingPathComponent("escape"),
                                      withDestinationURL: sandbox)
        let denied = root.appendingPathComponent("denied")
        try manager.createDirectory(at: denied, withIntermediateDirectories: true)
        precondition(chmod(denied.path, 0) == 0)
        defer { chmod(denied.path, 0o700) }
        let transport = FakeDiskTrash()
        let scanner = CleanDiskScanner(root: root, limits: .init(), crossVolumes: false,
                                       now: { Date(timeIntervalSince1970: 0) },
                                       transport: transport)
        let id = UUID()
        let scan = try await scanner.scan(id: id)
        precondition(!scan.nodes.contains { $0.path.lastPathComponent == "sentinel" })
        precondition(scan.nodes.contains { $0.path.path == denied.path && $0.unreadable })
        var info = stat()
        precondition(lstat(file.path, &info) == 0)
        let files = scan.nodes.filter { ["data", "hard"].contains($0.path.lastPathComponent) }
        precondition(files.reduce(0) { $0 + $1.allocatedSize } == UInt64(info.st_blocks) * 512)
        precondition(lstat(sparse.path, &info) == 0)
        precondition(scan.nodes.first { $0.path == sparse }?.allocatedSize == UInt64(info.st_blocks) * 512)
        precondition(scan.nodes[0].allocatedSize == scan.nodes.dropFirst().reduce(0) {
            $0 + $1.allocatedSize
        })
        var sentinelInfo = stat()
        precondition(lstat(sentinel.path, &sentinelInfo) == 0)
        let outside = CleanDiskScan.Node(
            path: sentinel, parent: 0, directory: false,
            device: UInt64(UInt32(bitPattern: sentinelInfo.st_dev)),
            inode: UInt64(sentinelInfo.st_ino), allocatedSize: 0)
        let forged = CleanDiskScan(id: id, root: scan.root, capturedAt: scan.capturedAt,
                                   nodes: [scan.nodes[0], outside], largestFiles: [], limited: false)
        do {
            try await scanner.trash(1, from: forged, currentID: id)
            fatalError("Outside item accepted")
        } catch {}
        do {
            _ = try await scanner.scan(id: id, isCurrent: { _ in false })
            fatalError("Stale result accepted")
        } catch is CancellationError {}
        let bounded = CleanDiskScanner(root: root, limits: .init(nodes: 1, largestFiles: 1),
                                       crossVolumes: false, now: { Date() },
                                       transport: FakeDiskTrash())
        let partial = try await bounded.scan(id: UUID())
        precondition(partial.limited && partial.nodes.count == 1)
        do {
            try await scanner.trash(0, from: scan, currentID: id)
            fatalError("Root accepted")
        } catch {}
        precondition(manager.fileExists(atPath: sentinel.path))
        precondition(transport.calls.withLock { $0.isEmpty })
        let selected = scan.nodes.firstIndex { $0.path == file }!
        try await scanner.trash(selected, from: scan, currentID: id)
        precondition(transport.calls.withLock { $0 == [file] })
        let task = Task {
            try await scanner.scan(id: UUID(), progress: { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        do { _ = try await task.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        print("PASS disk allocation, hard links, symlink, unreadable, refusal, cancellation")
    }
}
