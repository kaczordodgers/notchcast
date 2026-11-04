import Foundation

struct TodoFilterQuery: Equatable, Sendable {
    indirect enum Expression: Equatable, Sendable {
        case operand(Operand)
        case not(Expression)
        case and(Expression, Expression)
        case or(Expression, Expression)
    }

    enum Operand: Equatable, Sendable {
        case today
        case tomorrow
        case overdue
        case noDate
        case recurring
        case priority(Int)
        case project(String, includingSubprojects: Bool)
        case section(String)
        case label(String)
        case noLabels
        case search(String)
        case dueBefore(Date)
        case dueAfter(Date)
        /// Includes today and the following count minus one calendar days.
        case days(Int)
        case subtask
        case all
    }

    let lists: [Expression]
}
