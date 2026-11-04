import Foundation

/// The range uses UTF-16 offsets into the exact string supplied to the date parser.
struct TodoQuickAddDate: Equatable, Sendable {
    let range: NSRange
    let display: String
    let payload: String
}
