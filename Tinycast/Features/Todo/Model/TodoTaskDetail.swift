import Foundation

struct TodoTaskDetail: Equatable, Sendable {
    var task: TodoTask
    var ancestors: [TodoTask]
    var subtasks: [TodoTaskNode]
    var comments: [TodoComment]

    init?(id: String, state: TodoState, includeCompleted: Bool = false) {
        guard let task = state.tasks[id] else { return nil }
        self.task = task
        var path: [TodoTask] = []
        var parentID = task.parentID
        var visited: Set<String> = [id]
        while let id = parentID, visited.insert(id).inserted, let parent = state.tasks[id] {
            path.append(parent)
            parentID = parent.parentID
        }
        ancestors = path.reversed()
        let children = Dictionary(grouping: state.tasks.values, by: \.parentID)
        subtasks = Self.children(of: id, in: children, includeCompleted: includeCompleted)
        comments = task.comments.enumerated().sorted {
            let left = $0.element.createdAt
            let right = $1.element.createdAt
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }

    private static func children(of id: String, in children: [String?: [TodoTask]],
                                 includeCompleted: Bool) -> [TodoTaskNode] {
        (children[id] ?? []).sorted {
            $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }.flatMap { task -> [TodoTaskNode] in
            let descendants = Self.children(of: task.id, in: children, includeCompleted: includeCompleted)
            guard includeCompleted || task.completedAt == nil else { return descendants }
            return [TodoTaskNode(task: task, subtasks: descendants)]
        }
    }
}
