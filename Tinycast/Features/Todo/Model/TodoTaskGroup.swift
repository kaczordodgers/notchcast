import Foundation

struct TodoTaskGroup: Equatable, Identifiable, Sendable {
    var id: Key
    var tasks: [TodoTaskNode]

    enum Key: Hashable, Sendable {
        case all
        case project(String?)
        case section(String?)
        case priority(Int)
        case dueDate(Date?)
        case label(String?)
    }
}
