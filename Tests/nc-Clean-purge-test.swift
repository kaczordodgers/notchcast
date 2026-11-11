import Foundation

struct PurgeFakeTrash: CleanTrashTransport {
    let root: URL
    let receipts: URL

    func trash(_ url: URL) throws {
        precondition(url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"))
        try Data(url.path.utf8).write(to: receipts.appendingPathComponent(UUID().uuidString))
    }
}

@main
struct CleanPurgeTest {
    static func main() async throws {
        let manager = FileManager()
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let temp = temporary.resolvingSymlinksInPath()
        defer { try? manager.removeItem(at: temp) }
        let root = temp.appendingPathComponent("projects")
        let receipts = temp.appendingPathComponent("receipts")
        try manager.createDirectory(at: receipts, withIntermediateDirectories: true)
        let sentinel = temp.appendingPathComponent("sentinel")
        try Data("safe".utf8).write(to: sentinel)
        for name in ["idle", "active", "changed", "linked", "nested", "no-marker"] {
            let project = root.appendingPathComponent(name)
            try manager.createDirectory(at: project, withIntermediateDirectories: true)
            try Data().write(to: project.appendingPathComponent("package.json"))
            try Data().write(to: project.appendingPathComponent("package-lock.json"))
            if name == "linked" {
                try manager.createSymbolicLink(at: project.appendingPathComponent("node_modules"),
                    withDestinationURL: temp)
            } else {
                let artifact = project.appendingPathComponent("node_modules")
                try manager.createDirectory(at: artifact, withIntermediateDirectories: true)
                try Data(repeating: 1, count: 4096).write(to: artifact.appendingPathComponent("payload"))
                if name == "nested" { try Data().write(to: artifact.appendingPathComponent(".git")) }
            }
        }
        let loose = root.appendingPathComponent("unmarked")
        try manager.createDirectory(at: loose.appendingPathComponent("build"), withIntermediateDirectories: true)
        try manager.createDirectory(at: loose.appendingPathComponent("source_node_modules_helpers"),
            withIntermediateDirectories: true)
        let policy = CleanPurgePolicy(projectRoots: [root], now: Date(timeIntervalSince1970: 1000),
            recentActivityThreshold: 100, maximumDepth: 64, maximumEntries: 10000, protectedNames: [])
        let service = CleanPurgeService(policy: policy,
            transport: PurgeFakeTrash(root: root, receipts: receipts),
            activity: { project, _ in project.lastPathComponent == "active" ? .active : .idle },
            lastActivity: { project in
                Date(timeIntervalSince1970: project.lastPathComponent == "active" ? 999 : 0)
            })
        let items = try await service.scan()
        let timeoutService = CleanPurgeService(policy: policy,
            transport: PurgeFakeTrash(root: root, receipts: receipts),
            activity: { _, _ in throw POSIXError(.ETIMEDOUT) }, lastActivity: { _ in .distantPast })
        let unknown = try await timeoutService.scan()
        precondition(unknown.count == items.count && unknown.allSatisfy { $0.activity == .unknown })
        precondition(items.count == 4, "Found: \(items.map(\.path))")
        precondition(items.allSatisfy { $0.path.lastPathComponent == "node_modules" })
        precondition(items.allSatisfy { $0.allocatedSize >= 4096 })
        let initial = try manager.contentsOfDirectory(atPath: receipts.path)
        precondition(initial.isEmpty)
        try Data("changed".utf8).write(to: root.appendingPathComponent("changed/node_modules/payload"))
        let empty = try await service.clean([])
        precondition(empty.isEmpty)
        let results = try await service.clean(items.filter { $0.project.lastPathComponent != "no-marker" })
        precondition(results.filter { $0.status == .trashed }.count == 1,
            "Outcomes: \(results.map { "\($0.item.project.lastPathComponent): \($0.status)" })")
        precondition(results.filter { $0.status == .changedOrMissing }.count == 2)
        print("PASS: purge boundaries, activity, explicit selection, snapshots")
    }
}
