import Foundation

struct TodoQuickAddToken: Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        case project
        case section
        case label
        case priority
        case date
    }

    let kind: Kind
    /// UTF-16 offsets into the original input, including the token's marker.
    let range: NSRange
}
