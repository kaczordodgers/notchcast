import Foundation

struct TodoFilterError: Error, Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case unknownOperand(String)
        case missingOperand
        case unbalancedParenthesis
        case implicitAnd
        case unknownProject(String)
        case unknownLabel(String)
        case unknownSection(String)
        case invalidDate(String)
        case invalidDayCount
    }

    /// Offsets count Swift Characters, with an empty range marking an insertion point.
    let characterRange: Range<Int>
    let reason: Reason
}
