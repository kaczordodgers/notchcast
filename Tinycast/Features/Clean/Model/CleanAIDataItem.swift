import Foundation

struct CleanAIDataItem: Sendable {
    enum Kind: String, Sendable { case claude, codex, openCode, worktree }
    let path: URL
    let kind: Kind
    let selectable: Bool
    var refusal: Refusal?
    let size: Int64
    internal let snapshot: [String: String]

    enum Refusal: Sendable {
        case indexedStore, sessionSidecars, gitStateUnverified, chatNotIdle
    }
}
