// notchcast-sources: Tinycast/Features/Clean/Model/CleanDiskScan.swift
// notchcast-sources: Tinycast/Features/Clean/Service/CleanDiskDirectoryReader.swift
// notchcast-sources: Tinycast/Features/Clean/Service/CleanDiskScanner.swift
// notchcast-sources: Tinycast/Features/Clean/Service/CleanTrashTransport.swift
import Darwin
import Foundation
import Synchronization

final class ReviewedTrash: CleanTrashTransport {
    let calls = Mutex<[URL]>([])
    func trash(_ url: URL) throws { calls.withLock { $0.append(url) } }
}

@main
struct CleanReviewedTest {
    static func main() async throws {
        let manager = FileManager()
        let resolved = realpath(manager.temporaryDirectory.path, nil)!
        defer { free(resolved) }
        let root = URL(fileURLWithPath: String(cString: resolved))
            .appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let folder = root.appendingPathComponent("reviewed")
        let denied = folder.appendingPathComponent("denied")
        try manager.createDirectory(at: denied, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appendingPathComponent("original"))
        let transport = ReviewedTrash()
        let scanner = CleanDiskScanner(root: root, limits: .init(), crossVolumes: false,
                                       now: { Date() }, transport: transport)
        let scan = try await scanner.scan(id: UUID())
        let selected = scan.nodes.firstIndex { $0.path.lastPathComponent == "reviewed" }!
        try await scanner.trash(selected, from: scan, currentID: scan.id)
        precondition(transport.calls.withLock { $0.count == 1 })
        transport.calls.withLock { $0.removeAll() }
        print("PASS unchanged directory reaches recording transport")
        try Data([2]).write(to: folder.appendingPathComponent("added"))
        var refused = false
        do { try await scanner.trash(selected, from: scan, currentID: scan.id) } catch CleanDiskScanner.Failure.changed {
            refused = true
        }
        let addedSafe = refused && transport.calls.withLock { $0.isEmpty }
        print("\(addedSafe ? "PASS" : "FAIL") added file refuses directory execution")
        precondition(chmod(denied.path, 0) == 0)
        defer { chmod(denied.path, 0o700) }
        let incomplete = try await scanner.scan(id: UUID())
        let parentSafe = incomplete.nodes.first { $0.path.lastPathComponent == "reviewed" }!.unreadable
        print("\(parentSafe ? "PASS" : "FAIL") unreadable child makes parent report-only")
        precondition(chmod(denied.path, 0o700) == 0)
        let reviewed = try await scanner.scan(id: UUID())
        try Data([3, 4]).write(to: folder.appendingPathComponent("original"))
        var modifiedSafe = false
        do { try await scanner.trash(selected, from: reviewed, currentID: reviewed.id) } catch CleanDiskScanner.Failure.changed {
            modifiedSafe = true
        }
        print("\(modifiedSafe ? "PASS" : "FAIL") changed descendant refuses directory execution")
        guard addedSafe && parentSafe && modifiedSafe else { exit(1) }
    }
}
