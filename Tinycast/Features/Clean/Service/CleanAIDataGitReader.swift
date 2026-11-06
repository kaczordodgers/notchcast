import Foundation

protocol CleanAIDataGitReader: Sendable {
    func inspect(_ path: URL) async throws -> CleanAIDataGitState?
    func removeWorktreeMetadata(_ directory: URL, worktree: URL) throws
}

struct CleanAIDataWorktreeMetadata {
    static func verify(_ directory: URL, worktree: URL) throws {
        try Self.verifyDirectory(directory)
        let pointer = directory.appendingPathComponent("gitdir")
        let backlink = try Data(contentsOf: pointer)
        guard let text = String(data: backlink, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains("\n"), !text.contains("\0") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let base = URL(filePath: directory.path, directoryHint: .isDirectory)
        let target = URL(filePath: text, directoryHint: .notDirectory, relativeTo: base)
            .standardized.path
        let expected = worktree.appending(path: ".git", directoryHint: .notDirectory)
            .standardized.path
        guard target == expected else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSDebugDescriptionErrorKey: "Worktree backlink \(target) differs from \(expected)"
            ])
        }
    }

    private static func verifyDirectory(_ directory: URL) throws {
        let manager = FileManager()
        guard directory.deletingLastPathComponent().lastPathComponent == "worktrees",
              !manager.fileExists(atPath: directory.appendingPathComponent("locked").path) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var cursor = directory
        while cursor.path != "/" {
            let attributes = try manager.attributesOfItem(atPath: cursor.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw CocoaError(.fileWriteNoPermission)
            }
            cursor.deleteLastPathComponent()
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
