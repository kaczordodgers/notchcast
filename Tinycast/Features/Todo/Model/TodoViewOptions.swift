import Foundation

struct TodoViewOptions: Codable, Equatable, Sendable {
    var grouping: Grouping = .none
    var sorting: Sorting = .manual
    var includeCompleted = false

    enum Grouping: String, Codable, CaseIterable, Sendable {
        case none, project, section, priority, dueDate, label
    }

    enum Sorting: String, Codable, CaseIterable, Sendable {
        case manual, due, priority, name, added
    }
}
