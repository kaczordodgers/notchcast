import Foundation

struct TodoRecordChange<Value: Codable & Equatable & Identifiable & Sendable>: Codable, Equatable, Sendable
    where Value.ID == String {
    let before: Value?
    let after: Value?
    var restoredFrom: TodoEnvelope.ID?
}

struct TodoRecordIdentity: Hashable, Sendable {
    let kind: TodoCommand.Entity
    let id: String
}

struct TodoOrphanRecovery: Codable, Equatable, Sendable {
    let taskID: String
    let projectID: String?
    let parentID: String?
}

struct TodoReplicationChanges: Codable, Equatable, Sendable {
    var tasks: [TodoRecordChange<TodoTask>]
    var projects: [TodoRecordChange<TodoProject>]
    var sections: [TodoRecordChange<TodoSection>]
    var labels: [TodoRecordChange<TodoLabel>]
    var filters: [TodoRecordChange<TodoSavedFilter>]

    var hasRestorations: Bool {
        tasks.contains { $0.restoredFrom != nil } || projects.contains { $0.restoredFrom != nil }
            || sections.contains { $0.restoredFrom != nil } || labels.contains { $0.restoredFrom != nil }
            || filters.contains { $0.restoredFrom != nil }
    }

    mutating func markRestorations(_ deletions: [TodoRecordIdentity: TodoEnvelope.ID]) {
        Self.mark(&tasks, kind: .task, deletions: deletions)
        Self.mark(&projects, kind: .project, deletions: deletions)
        Self.mark(&sections, kind: .section, deletions: deletions)
        Self.mark(&labels, kind: .label, deletions: deletions)
        Self.mark(&filters, kind: .filter, deletions: deletions)
    }

    private static func mark<Value>(_ changes: inout [TodoRecordChange<Value>], kind: TodoCommand.Entity,
                                    deletions: [TodoRecordIdentity: TodoEnvelope.ID]) {
        for index in changes.indices where changes[index].before == nil {
            if let id = changes[index].after?.id {
                changes[index].restoredFrom = deletions[TodoRecordIdentity(kind: kind, id: id)]
            }
        }
    }

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

struct TodoReplicationProjection: Sendable {
    private var tasks: [String: TodoTask] = [:]
    private var projects: [String: TodoProject] = [:]
    private var sections: [String: TodoSection] = [:]
    private var labels: [String: TodoLabel] = [:]
    private var filters: [String: TodoSavedFilter] = [:]
    private var deletions: [TodoRecordIdentity: [TodoEnvelope.ID]] = [:]
    private(set) var latestDeletes: [TodoRecordIdentity: TodoEnvelope.ID] = [:]

    mutating func apply(_ envelope: TodoEnvelope) throws {
        let changes = envelope.changes
        try Self.apply(changes.tasks, kind: .task, envelopeID: envelope.id, to: &tasks,
                       deletions: &deletions, latestDeletes: &latestDeletes, merge: Self.mergeTask)
        try Self.apply(changes.projects, kind: .project, envelopeID: envelope.id, to: &projects,
                       deletions: &deletions, latestDeletes: &latestDeletes) { current, change in
            Self.assign(\TodoProject.name, to: &current, change: change)
            Self.assign(\TodoProject.order, to: &current, change: change)
        }
        try Self.apply(changes.sections, kind: .section, envelopeID: envelope.id, to: &sections,
                       deletions: &deletions, latestDeletes: &latestDeletes) { current, change in
            Self.assign(\TodoSection.name, to: &current, change: change)
            Self.assign(\TodoSection.projectID, to: &current, change: change)
            Self.assign(\TodoSection.order, to: &current, change: change)
        }
        try Self.apply(changes.labels, kind: .label, envelopeID: envelope.id, to: &labels,
                       deletions: &deletions, latestDeletes: &latestDeletes) { current, change in
            Self.assign(\TodoLabel.name, to: &current, change: change)
            Self.assign(\TodoLabel.order, to: &current, change: change)
        }
        try Self.apply(changes.filters, kind: .filter, envelopeID: envelope.id, to: &filters,
                       deletions: &deletions, latestDeletes: &latestDeletes) { current, change in
            Self.assign(\TodoSavedFilter.name, to: &current, change: change)
            Self.assign(\TodoSavedFilter.query, to: &current, change: change)
            Self.assign(\TodoSavedFilter.order, to: &current, change: change)
        }
    }

    private static func apply<Value>(_ changes: [TodoRecordChange<Value>], kind: TodoCommand.Entity,
                                     envelopeID: TodoEnvelope.ID, to values: inout [String: Value],
                                     deletions: inout [TodoRecordIdentity: [TodoEnvelope.ID]],
                                     latestDeletes: inout [TodoRecordIdentity: TodoEnvelope.ID],
                                     merge: (inout Value, TodoRecordChange<Value>) -> Void) throws {
        for change in changes {
            guard let id = change.after?.id ?? change.before?.id, UUID(uuidString: id) != nil,
                  change.before == nil || change.after == nil || change.before?.id == change.after?.id else {
                throw TodoReplicationError.invalidEnvelope
            }
            let key = TodoRecordIdentity(kind: kind, id: id)
            if change.after == nil {
                values.removeValue(forKey: id)
                deletions[key, default: []].append(envelopeID)
                latestDeletes[key] = envelopeID
            } else if change.before == nil {
                if let restoredFrom = change.restoredFrom {
                    deletions[key]?.removeAll { $0 == restoredFrom }
                    latestDeletes[key] = deletions[key]?.last
                }
                if deletions[key]?.isEmpty != false { values[id] = change.after }
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
        assign(\.addedAt, to: &current, change: change)
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

    func materialize() throws -> (state: TodoState, orphans: [TodoOrphanRecovery]) {
        let validSections = sections.filter { projects[$0.value.projectID] != nil }
        var validTasks = tasks
        var orphans: [TodoOrphanRecovery] = []
        for id in validTasks.keys.sorted() {
            guard var task = validTasks[id] else { continue }
            if task.projectID.map({ projects[$0] == nil }) == true || task.parentID.map({ tasks[$0] == nil }) == true {
                orphans.append(TodoOrphanRecovery(taskID: id, projectID: task.projectID, parentID: task.parentID))
                task.projectID = nil
                task.sectionID = nil
                task.parentID = nil
            }
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
        return (try TodoState.replicated(tasks: validTasks, projects: projects, sections: validSections,
                                         labels: labels, filters: filters), orphans)
    }
}
