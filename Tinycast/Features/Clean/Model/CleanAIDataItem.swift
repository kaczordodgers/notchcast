import Foundation

struct CleanAIDataItem: Sendable {
    enum Kind: String, Sendable { case claude, codex, openCode, worktree }
    let path: URL
    let kind: Kind
    let selectable: Bool
    let selected = false
    internal let snapshot: [String: String]
}
