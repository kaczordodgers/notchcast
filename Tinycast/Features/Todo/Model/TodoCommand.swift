import Foundation

indirect enum TodoCommand: Codable, Equatable, Sendable {
    case addTask(TodoTask)
    case updateTask(TodoTask)
    case moveTask(id: String, projectID: String?, sectionID: String?, parentID: String?)
    case completeTask(id: String, at: Date)
    case uncompleteTask(id: String)
    case deleteTask(id: String)
    case addProject(TodoProject)
    case renameProject(id: String, name: String)
    case deleteProject(id: String)
    case addSection(TodoSection)
    case renameSection(id: String, name: String)
    case deleteSection(id: String)
    case addLabel(TodoLabel)
    case renameLabel(id: String, name: String)
    case deleteLabel(id: String)
    case addFilter(TodoSavedFilter)
    case renameFilter(id: String, name: String)
    case updateFilter(TodoSavedFilter)
    case deleteFilter(id: String)
    case addComment(taskID: String, comment: TodoComment)
    case reorder(kind: Entity, orders: [String: Int])
    // Inverses remove exact records without cascading into another inverse in the same batch.
    case removeRecord(kind: Entity, id: String)
    case batch([TodoCommand])

    enum Entity: String, Codable, Hashable, Sendable {
        case task, project, section, label, filter
    }
}
