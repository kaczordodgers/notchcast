import Foundation

protocol TodoFilterSubject: Sendable {
    var title: String { get }
    var projectName: String? { get }
    /// Root-to-leaf project names, including the task's own project.
    var projectPath: [String] { get }
    var sectionName: String? { get }
    var labels: [String] { get }
    /// Storage priority runs from 1 (P4) to 4 (P1).
    var priority: Int { get }
    var dueDate: Date? { get }
    var hasTime: Bool { get }
    var isRecurring: Bool { get }
    var isSubtask: Bool { get }
    var isCompleted: Bool { get }
}
