import Foundation

/// Priority runs from 1 to 4; 4 is the most urgent and is displayed as P1.
struct TodoTask: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var description = ""
    var projectID: String?
    var sectionID: String?
    var parentID: String?
    var priority = 1
    var due: Due?
    var labels: [String] = []
    var order = 0
    var completedAt: Date?
    var comments: [TodoComment] = []
    var externalRef: String?
    var claim: TodoAgentClaim?
    var addedAt: Date?

    struct Due: Codable, Equatable, Sendable {
        var date: Date
        var time: DateComponents?
        var isAllDay: Bool
        var recurrenceRule: String?
        var normalized: String
    }
}
