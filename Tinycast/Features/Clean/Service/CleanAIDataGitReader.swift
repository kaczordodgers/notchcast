import Foundation

protocol CleanAIDataGitReader: Sendable {
    func inspect(_ path: URL) async throws -> CleanAIDataGitState?
    func removeWorktreeMetadata(_ directory: URL, worktree: URL) throws
}

struct CleanAIDataWorktreeMetadata {
    static func verify(_ directory: URL, worktree: URL) throws {
        let manager = FileManager()
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              directory.standardized.path == directory.resolvingSymlinksInPath().path,
              directory.deletingLastPathComponent().lastPathComponent == "worktrees",
              !manager.fileExists(atPath: directory.appendingPathComponent("locked").path) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let pointer = directory.appendingPathComponent("gitdir")
        let text = try String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\n"), !text.contains("\0") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let base = URL(filePath: directory.path, directoryHint: .isDirectory)
        let backlink = URL(filePath: text, directoryHint: .notDirectory, relativeTo: base).standardized.path
        let expected = worktree.appending(path: ".git", directoryHint: .notDirectory).standardized.path
        guard backlink == expected else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSDebugDescriptionErrorKey: "Worktree backlink \(backlink) differs from \(expected)"
            ])
        }
    }

    static func remove(_ directory: URL, worktree: URL) throws {
        try verify(directory, worktree: worktree)
        try FileManager().removeItem(at: directory)
    }
}

struct CleanAIDataGitState: Sendable {
    let linked: Bool
    let locked: Bool
    let dirty: Bool
    let unpushed: Bool
    let mergedIntoMain: Bool
    let hiddenIndexFlags: Bool
    let submodules: Bool
    let operationInProgress: Bool
    let idle: Bool

    var eligible: Bool {
        linked && !locked && !dirty && !unpushed && mergedIntoMain && !hiddenIndexFlags
            && !submodules && !operationInProgress && idle
    }
}
