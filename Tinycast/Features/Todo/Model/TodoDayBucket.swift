import Foundation

struct TodoDayBucket: Equatable, Identifiable, Sendable {
    var id: Key
    var groups: [TodoTaskGroup]

    enum Key: Hashable, Sendable {
        case overdue
        case day(Date)
    }
}
