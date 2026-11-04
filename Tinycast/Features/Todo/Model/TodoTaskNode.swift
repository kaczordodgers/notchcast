import Foundation

struct TodoTaskNode: Equatable, Identifiable, Sendable {
    var task: TodoTask
    var subtasks: [TodoTaskNode] = []
    var id: String { task.id }
}
