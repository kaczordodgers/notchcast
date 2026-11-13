import Foundation

struct AITrash: CleanTrashTransport {
    let receipts: URL
    func trash(_ url: URL) throws {
        try Data(url.path.utf8).write(to: receipts.appendingPathComponent(UUID().uuidString))
        if url.deletingLastPathComponent().lastPathComponent == "wt" {
            try FileManager().moveItem(at: url, to: receipts.appendingPathComponent("trashed-worktree"))
        }
    }
}

struct AIGit: CleanAIDataGitReader {
    let receipt: URL
    func removeWorktreeMetadata(_ directory: URL, worktree: URL) throws {
        precondition(!FileManager().fileExists(atPath:
            receipt.deletingLastPathComponent().appendingPathComponent("fixture/agents/wt/clean").path))
        try CleanAIDataWorktreeMetadata.remove(directory, worktree: worktree)
        try Data(directory.path.utf8).write(to: receipt)
    }
    func inspect(_ path: URL) throws -> CleanAIDataGitState? {
        let name = path.lastPathComponent
        if name == "unknown" { return nil }
        return .init(linked: true, locked: name == "locked", dirty: name == "dirty",
                     unpushed: name == "unpushed", mergedIntoMain: true, hiddenIndexFlags: false,
                     submodules: false, operationInProgress: false, idle: true)
    }
}

@main
struct CleanAIDataTest {
    static func main() async throws {
        let manager = FileManager()
        let scratch = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) }
            ?? manager.temporaryDirectory
        let temp = scratch.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: temp, withIntermediateDirectories: true)
        guard let resolved = realpath(temp.path, nil) else { throw CocoaError(.fileReadUnknown) }
        defer { free(resolved) }
        let base = URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: base) }
        let home = base.appendingPathComponent("fixture")
        let metadataRoot = base.appendingPathComponent("repo/.git/worktrees")
        let sibling = metadataRoot.appendingPathComponent("missing-sibling")
        try manager.createDirectory(at: sibling, withIntermediateDirectories: true)
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
        for name in ["clean", "dirty", "unpushed", "locked", "unknown", "recent"] {
            let tree = home.appendingPathComponent("agents/wt/" + name)
            try manager.createDirectory(at: tree, withIntermediateDirectories: true)
            let metadata = metadataRoot.appendingPathComponent(name)
            try manager.createDirectory(at: metadata, withIntermediateDirectories: true)
            try Data(tree.appendingPathComponent(".git").path.utf8)
                .write(to: metadata.appendingPathComponent("gitdir"))
            try Data("gitdir: \(metadata.path)".utf8)
                .write(to: tree.appendingPathComponent(".git"))
            try manager.setAttributes([.modificationDate: old], ofItemAtPath: tree.appendingPathComponent(".git").path)
            try manager.setAttributes([.modificationDate: name == "recent" ? clock : old],
                                      ofItemAtPath: tree.path)
        }
        for root in [".codex/sessions/2020", ".local/share/opencode/storage/session/project"] {
            let directory = home.appendingPathComponent(root)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let session = directory.appendingPathComponent("session.jsonl")
            try bytes.write(to: session)
            try manager.setAttributes([.modificationDate: old], ofItemAtPath: session.path)
        }
        let index = home.appendingPathComponent(".codex/session_index.jsonl")
        try bytes.write(to: index)
        let pruneReceipt = base.appendingPathComponent("pruned")
        let policy = CleanAIDataPolicy(home: home, age: CleanAIDataPolicy.defaultAge)
        let service = CleanAIDataService(policy: policy, transport: AITrash(receipts: receipts),
            git: AIGit(receipt: pruneReceipt), now: { clock }, chatIdle: { _ in true }, copy: { _, destination in
                try Data("corrupted".utf8).write(to: destination)
            })
        let items = try await service.scan()
        let recorded = try manager.contentsOfDirectory(atPath: receipts.path)
        precondition(recorded.isEmpty)
        let link = base.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: home)
        precondition(!CleanService.physical(home, inside: home) && CleanService.physical(chat, inside: home))
        precondition(!CleanService.physical(link.appendingPathComponent(".claude"), inside: base))
        precondition(!CleanService.physical(home.appendingPathComponent(".claude/.."), inside: home))
        precondition(!CleanService.physical(sentinel, inside: home))
        print("PASS: one trash-safety check refuses links, dot segments and paths outside the root")
        precondition(items.filter { $0.selectable }.count == 2)
        let indexed = items.filter { $0.kind == .codex || $0.kind == .openCode }
        precondition(indexed.count == 2 && indexed.allSatisfy { !$0.selectable && $0.refusal == .indexedStore })
        let indexedOutcomes = try await service.clean(indexed)
        precondition(indexedOutcomes.allSatisfy { $0.status == .refused })
        precondition(!policy.permits(base.appendingPathComponent("outside.jsonl"), kind: .claude))
        precondition(!policy.permits(project.appendingPathComponent("../bad.jsonl"), kind: .claude))
        precondition(!policy.permits(project.appendingPathComponent(".hidden.jsonl"), kind: .claude))
        precondition(!items.contains { $0.path.lastPathComponent == "recent" })
        let empty = try await service.clean([])
        precondition(empty.isEmpty)
        let failed = try await service.clean(items.filter { $0.kind == .claude })
        precondition(!manager.fileExists(atPath: home.appendingPathComponent(".clean-ai-recovery").path),
                     "Clean must not leave private recovery copies")
        precondition(failed.first?.status == .recoveryFailed, String(describing: failed))
        let outcomes = try await service.clean(items.filter { $0.kind == .worktree })
        precondition(outcomes.filter { $0.status == .trashed }.count == 1, String(describing: outcomes))
        precondition(outcomes.filter { $0.status == .refused }.count == 4)
        let pruned = try String(contentsOf: pruneReceipt, encoding: .utf8)
        precondition(pruned == metadataRoot.appendingPathComponent("clean").path)
        precondition(!manager.fileExists(atPath: pruned))
        precondition(manager.fileExists(atPath: sibling.path))
        for name in ["wrong", "symlink", "locked", "relative"] {
            let directory = metadataRoot.appendingPathComponent(name)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let tree = base.appendingPathComponent("checkout")
            let backPointer = name == "relative" ? "../../../../checkout/.git"
                : (name == "wrong" ? "/wrong/.git" : tree.appendingPathComponent(".git").path)
            try Data(backPointer.utf8).write(to: directory.appendingPathComponent("gitdir"))
            if name == "locked" { try Data().write(to: directory.appendingPathComponent("locked")) }
            let target: URL
            if name == "symlink" {
                target = metadataRoot.appendingPathComponent("link")
                try manager.createSymbolicLink(at: target, withDestinationURL: directory)
            } else { target = directory }
            do {
                try CleanAIDataWorktreeMetadata.remove(target, worktree: tree)
                precondition(name == "relative")
            } catch {
                precondition(name != "relative")
                precondition(manager.fileExists(atPath: directory.path))
                print("PASS: reported unsafe metadata: \(name)")
            }
        }
        for name in ["changed-backlink", "new-lock"] {
            let directory = metadataRoot.appendingPathComponent(name)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let tree = base.appendingPathComponent("checkout")
            let pointer = directory.appendingPathComponent("gitdir")
            try Data(tree.appendingPathComponent(".git").path.utf8).write(to: pointer)
            try CleanAIDataWorktreeMetadata.verify(directory, worktree: tree)
            if name == "new-lock" {
                try Data().write(to: directory.appendingPathComponent("locked"))
            } else { try Data("/wrong/.git".utf8).write(to: pointer) }
            do {
                try CleanAIDataWorktreeMetadata.remove(directory, worktree: tree)
                preconditionFailure("Changed metadata was removed")
            } catch {
                precondition(manager.fileExists(atPath: directory.path))
                print("PASS: reported metadata change before removal: \(name)")
            }
        }
        let recovering = CleanAIDataService(policy: policy, transport: AITrash(receipts: receipts),
            git: AIGit(receipt: pruneReceipt), now: { clock }, chatIdle: { _ in true }, copy: {
                try FileManager().copyItem(at: $0, to: $1)
            })
        let recovered = try await recovering.clean(items.filter { $0.kind == .claude })
        precondition(recovered.first?.status == .trashed)
        let backup = try Data(contentsOf: recovered[0].recovery!)
        precondition(backup == bytes)
        let sidecar = chat.deletingPathExtension()
        try manager.createDirectory(at: sidecar, withIntermediateDirectories: false)
        let sidecarScan = try await recovering.scan()
        precondition(sidecarScan.contains {
            $0.path.lastPathComponent == chat.lastPathComponent && !$0.selectable && $0.refusal == .sessionSidecars
        }, String(describing: sidecarScan))
        print("PASS: only trashed metadata removed; missing sibling preserved; relative gitdir accepted")
        print("PASS: indexed stores and sidecars refused; recovery verified; unsafe paths refused")
    }
}
