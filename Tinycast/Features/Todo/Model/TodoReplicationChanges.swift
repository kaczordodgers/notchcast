import Foundation

struct TodoRecordChange<Value: Codable & Equatable & Identifiable & Sendable>: Codable, Equatable, Sendable
    where Value.ID == String {
    let before: Value?
    let after: Value?
}

struct TodoReplicationChanges: Codable, Equatable, Sendable {
    var tasks: [TodoRecordChange<TodoTask>]
    var projects: [TodoRecordChange<TodoProject>]
    var sections: [TodoRecordChange<TodoSection>]
    var labels: [TodoRecordChange<TodoLabel>]
    var filters: [TodoRecordChange<TodoSavedFilter>]

    init(command: TodoCommand, before: TodoState, after: TodoState) {
        let taskID: String?
        switch command {
        case .addTask(let task), .updateTask(let task): taskID = task.id
        case .completeTask(let id, _), .uncompleteTask(let id), .addComment(let id, _): taskID = id
        default: taskID = nil
        }
        if let taskID {
            tasks = before.tasks[taskID] == after.tasks[taskID] ? []
                : [TodoRecordChange(before: before.tasks[taskID], after: after.tasks[taskID])]
        } else {
            tasks = Self.changes(before.tasks, after.tasks)
        }
        projects = Self.changes(before.projects, after.projects)
        sections = Self.changes(before.sections, after.sections)
        labels = Self.changes(before.labels, after.labels)
        filters = Self.changes(before.filters, after.filters)
    }

    private static func changes<Value>(_ before: [String: Value], _ after: [String: Value]) -> [TodoRecordChange<Value>] {
        guard before != after else { return [] }
        return Set(before.keys).union(after.keys).sorted().compactMap { id in
            before[id] == after[id] ? nil : TodoRecordChange(before: before[id], after: after[id])
        }
    }
}

struct TodoReplicationProjection {
    private var tasks: [String: TodoTask] = [:]
    private var projects: [String: TodoProject] = [:]
    private var sections: [String: TodoSection] = [:]
    private var labels: [String: TodoLabel] = [:]
    private var filters: [String: TodoSavedFilter] = [:]

    mutating func apply(_ changes: TodoReplicationChanges) throws {
        try Self.apply(changes.tasks, to: &tasks, merge: Self.mergeTask)
        try Self.apply(changes.projects, to: &projects) { current, change in
            Self.assign(\TodoProject.name, to: &current, change: change)
            Self.assign(\TodoProject.order, to: &current, change: change)
        }
        try Self.apply(changes.sections, to: &sections) { current, change in
            Self.assign(\TodoSection.name, to: &current, change: change)
            Self.assign(\TodoSection.projectID, to: &current, change: change)
            Self.assign(\TodoSection.order, to: &current, change: change)
        }
        try Self.apply(changes.labels, to: &labels) { current, change in
            Self.assign(\TodoLabel.name, to: &current, change: change)
            Self.assign(\TodoLabel.order, to: &current, change: change)
        }
        try Self.apply(changes.filters, to: &filters) { current, change in
            Self.assign(\TodoSavedFilter.name, to: &current, change: change)
            Self.assign(\TodoSavedFilter.query, to: &current, change: change)
            Self.assign(\TodoSavedFilter.order, to: &current, change: change)
        }
    }

    private static func apply<Value>(_ changes: [TodoRecordChange<Value>], to values: inout [String: Value],
                                     merge: (inout Value, TodoRecordChange<Value>) -> Void) throws {
        for change in changes {
            guard let id = change.after?.id ?? change.before?.id, UUID(uuidString: id) != nil,
                  change.before == nil || change.after == nil || change.before?.id == change.after?.id else {
                throw TodoReplicationError.invalidEnvelope
            }
            if change.after == nil {
                values.removeValue(forKey: id)
            } else if change.before == nil {
                values[id] = change.after
            } else if var current = values[id] {
                merge(&current, change)
                values[id] = current
            }
        }
    }

    private static func assign<Value, Field: Equatable>(
        _ key: WritableKeyPath<Value, Field>, to current: inout Value, change: TodoRecordChange<Value>
    ) {
        guard let after = change.after, change.before?[keyPath: key] != after[keyPath: key] else { return }
        current[keyPath: key] = after[keyPath: key]
    }

    private static func mergeTask(_ current: inout TodoTask, _ change: TodoRecordChange<TodoTask>) {
        assign(\.title, to: &current, change: change)
        assign(\.description, to: &current, change: change)
        assign(\.due, to: &current, change: change)
        assign(\.priority, to: &current, change: change)
        assign(\.labels, to: &current, change: change)
        assign(\.completedAt, to: &current, change: change)
        assign(\.order, to: &current, change: change)
        assign(\.externalRef, to: &current, change: change)
        assign(\.claim, to: &current, change: change)
        if let after = change.after,
           change.before?.projectID != after.projectID || change.before?.sectionID != after.sectionID
            || change.before?.parentID != after.parentID {
            current.projectID = after.projectID
            current.sectionID = after.sectionID
            current.parentID = after.parentID
        }
        guard let after = change.after, change.before?.comments != after.comments else { return }
        if current.comments == change.before?.comments {
            current.comments = after.comments
            return
        }
        let before = Dictionary((change.before?.comments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let next = Dictionary(after.comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var comments = Dictionary(current.comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in Set(before.keys).union(next.keys) where before[id] != next[id] { comments[id] = next[id] }
        current.comments = comments.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
    }

    func state() throws -> TodoState {
        let validSections = sections.filter { projects[$0.value.projectID] != nil }
        var validTasks = tasks.filter { $0.value.projectID.map { projects[$0] != nil } ?? true }
        while validTasks.values.contains(where: { $0.parentID.map { validTasks[$0] == nil } ?? false }) {
            validTasks = validTasks.filter { $0.value.parentID.map { validTasks[$0] != nil } ?? true }
        }
        for id in validTasks.keys.sorted() {
            guard var task = validTasks[id] else { continue }
            if let sectionID = task.sectionID, validSections[sectionID]?.projectID != task.projectID { task.sectionID = nil }
            task.labels = task.labels.filter { labels[$0] != nil }
            validTasks[id] = task
        }
        for id in validTasks.keys.sorted() {
            var visited: Set<String> = []
            var cursor: String? = id
            while let current = cursor, let task = validTasks[current] {
                guard visited.insert(current).inserted else {
                    validTasks[current]?.parentID = nil
                    break
                }
                cursor = task.parentID
            }
        }
        for id in validTasks.keys.sorted() {
            var rootID = id
            while let parentID = validTasks[rootID]?.parentID { rootID = parentID }
            let root = validTasks[rootID]
            validTasks[id]?.projectID = root?.projectID
            validTasks[id]?.sectionID = root?.sectionID
        }
        var result = TodoState()
        try result.apply(.batch(projects.values.sorted { $0.id < $1.id }.map(TodoCommand.addProject)
            + validSections.values.sorted { $0.id < $1.id }.map(TodoCommand.addSection)
            + labels.values.sorted { $0.id < $1.id }.map(TodoCommand.addLabel)
            + filters.values.sorted { $0.id < $1.id }.map(TodoCommand.addFilter)
            + validTasks.values.sorted { $0.id < $1.id }.map(TodoCommand.addTask)))
        return result
    }
}
