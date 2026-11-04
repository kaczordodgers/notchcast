import Foundation

struct AITrash: CleanTrashTransport {
    let receipts: URL
    func trash(_ url: URL) throws {
        try Data(url.path.utf8).write(to: receipts.appendingPathComponent(UUID().uuidString))
    }
}

struct AIGit: CleanAIDataGitReader {
    func inspect(_ path: URL) throws -> CleanAIDataGitState? {
        let name = path.lastPathComponent
        if name == "unknown" { return nil }
        return .init(linked: true, locked: false, dirty: name == "dirty",
                     unpushed: name == "unpushed", mergedIntoMain: true, hiddenIndexFlags: false,
                     submodules: false, operationInProgress: false, idle: true)
    }
}

@main
struct CleanAIDataTest {
    static func main() async throws {
        let manager = FileManager()
        let temp = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: temp, withIntermediateDirectories: true)
        let base = temp.resolvingSymlinksInPath()
        defer { try? manager.removeItem(at: base) }
        let home = base.appendingPathComponent("fixture")
        let receipts = base.appendingPathComponent("receipts")
        try manager.createDirectory(at: receipts, withIntermediateDirectories: true)
        let sentinel = base.appendingPathComponent("sentinel")
        try Data("safe".utf8).write(to: sentinel)
        let project = home.appendingPathComponent(".claude/projects/project")
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        let chat = project.appendingPathComponent(UUID().uuidString + ".jsonl")
        let bytes = Data("chat".utf8)
        try bytes.write(to: chat)
        let clock = Date(timeIntervalSince1970: 2_000_000_000)
        let old = clock.addingTimeInterval(-30 * 86_400)
        try manager.setAttributes([.modificationDate: old], ofItemAtPath: chat.path)
        try manager.createSymbolicLink(at: project.appendingPathComponent(UUID().uuidString + ".jsonl"),
                                       withDestinationURL: sentinel)
        for name in ["clean", "dirty", "unpushed", "unknown", "recent"] {
            let tree = home.appendingPathComponent("agents/wt/" + name)
            try manager.createDirectory(at: tree, withIntermediateDirectories: true)
            try manager.setAttributes([.modificationDate: name == "recent" ? clock : old],
                                      ofItemAtPath: tree.path)
        }
        let policy = CleanAIDataPolicy(home: home, age: CleanAIDataPolicy.defaultAge)
        let service = CleanAIDataService(policy: policy, transport: AITrash(receipts: receipts),
            git: AIGit(), now: { clock }, chatIdle: { _ in true }, copy: { _, destination in
                try Data("corrupted".utf8).write(to: destination)
            })
        let items = try await service.scan()
        precondition(items.allSatisfy { !$0.selected })
        let recorded = try manager.contentsOfDirectory(atPath: receipts.path)
        precondition(recorded.isEmpty)
        precondition(items.filter { $0.selectable }.count == 2)
        precondition(!items.contains { $0.path.lastPathComponent == "recent" })
        let empty = try await service.clean([])
        precondition(empty.isEmpty)
        let failed = try await service.clean(items.filter { $0.kind == .claude })
        precondition(failed.first?.status == .recoveryFailed, String(describing: failed))
        let unchanged = try Data(contentsOf: chat)
        precondition(unchanged == bytes)
        let outcomes = try await service.clean(items.filter { $0.kind == .worktree })
        precondition(outcomes.filter { $0.status == .trashed }.count == 1)
        precondition(outcomes.filter { $0.status == .refused }.count == 3)
        let surviving = try Data(contentsOf: sentinel)
        precondition(surviving == Data("safe".utf8))
        print("PASS: scan read-only, unselected, recovery verification, git refusal, symlink, sentinel")
    }
}
