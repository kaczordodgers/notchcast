import Foundation

struct TodoState: Codable, Equatable, Sendable {
    private(set) var tasks: [String: TodoTask] = [:]
    private(set) var projects: [String: TodoProject] = [:]
    private(set) var sections: [String: TodoSection] = [:]
    private(set) var labels: [String: TodoLabel] = [:]
    private(set) var filters: [String: TodoSavedFilter] = [:]

    static func replicated(tasks: [String: TodoTask], projects: [String: TodoProject],
                           sections: [String: TodoSection], labels: [String: TodoLabel],
                           filters: [String: TodoSavedFilter]) throws -> TodoState {
        var result = TodoState()
        result.tasks = tasks
        result.projects = projects
        result.sections = sections
        result.labels = labels
        result.filters = filters
        try result.validate()
        return result
    }

    @discardableResult
    mutating func apply(_ command: TodoCommand) throws -> TodoCommand {
        var candidate = self
        let inverse = try candidate.applyUnchecked(command)
        if case .addTask(let task) = command {
            try candidate.validate(task)
        } else {
            try candidate.validate()
        }
        self = candidate
        return inverse
    }

    private mutating func applyUnchecked(_ command: TodoCommand) throws -> TodoCommand {
        switch command {
        case .addTask(let task):
            try insert(task, into: &tasks)
            return .removeRecord(kind: .task, id: task.id)
        case .updateTask(let task):
            let previous = try required(tasks, task.id, .task)
            tasks[task.id] = task
            return .updateTask(previous)
        case .moveTask(let id, let projectID, let sectionID, let parentID):
            _ = try required(tasks, id, .task)
            let ids = descendants(of: id)
            if let parentID, ids.contains(parentID) { throw TodoCommandError.parentCycle(id) }
            if let sectionID {
                let section = try required(sections, sectionID, .section)
                guard section.projectID == projectID else { throw TodoCommandError.sectionProjectMismatch(id) }
            }
            let previous = ids.compactMap { tasks[$0] }
            for taskID in ids {
                tasks[taskID]?.projectID = projectID
                tasks[taskID]?.sectionID = sectionID
            }
            tasks[id]?.parentID = parentID
            return .batch(previous.map(TodoCommand.updateTask))
        case .completeTask(let id, let date):
            let previous = try required(tasks, id, .task)
            tasks[id]?.completedAt = date
            return .updateTask(previous)
        case .uncompleteTask(let id):
            let previous = try required(tasks, id, .task)
            tasks[id]?.completedAt = nil
            return .updateTask(previous)
        case .deleteTask(let id):
            _ = try required(tasks, id, .task)
            let removed = descendants(of: id).compactMap { tasks.removeValue(forKey: $0) }
            return .batch(removed.map(TodoCommand.addTask))
        case .addProject(let project):
            try insert(project, into: &projects)
            return .removeRecord(kind: .project, id: project.id)
        case .renameProject(let id, let name):
            let previous = try required(projects, id, .project)
            projects[id]?.name = name
            return .renameProject(id: id, name: previous.name)
        case .deleteProject(let id):
            let previous = try required(projects, id, .project)
            let removedTasks = tasks.values.filter { $0.projectID == id }.sorted { $0.id < $1.id }
            let removedSections = sections.values.filter { $0.projectID == id }.sorted { $0.id < $1.id }
            for task in removedTasks { tasks.removeValue(forKey: task.id) }
            for section in removedSections { sections.removeValue(forKey: section.id) }
            projects.removeValue(forKey: id)
            return .batch([.addProject(previous)] + removedSections.map(TodoCommand.addSection)
                + removedTasks.map(TodoCommand.addTask))
        case .addSection(let section):
            try insert(section, into: &sections)
            return .removeRecord(kind: .section, id: section.id)
        case .renameSection(let id, let name):
            let previous = try required(sections, id, .section)
            sections[id]?.name = name
            return .renameSection(id: id, name: previous.name)
        case .deleteSection(let id):
            let previous = try required(sections, id, .section)
            let affected = tasks.values.filter { $0.sectionID == id }.sorted { $0.id < $1.id }
            for task in affected { tasks[task.id]?.sectionID = nil }
            sections.removeValue(forKey: id)
            return .batch([.addSection(previous)] + affected.map(TodoCommand.updateTask))
        case .addLabel(let label):
            try insert(label, into: &labels)
            return .removeRecord(kind: .label, id: label.id)
        case .renameLabel(let id, let name):
            let previous = try required(labels, id, .label)
            labels[id]?.name = name
            return .renameLabel(id: id, name: previous.name)
        case .deleteLabel(let id):
            let previous = try required(labels, id, .label)
            let affected = tasks.values.filter { $0.labels.contains(id) }.sorted { $0.id < $1.id }
            for task in affected { tasks[task.id]?.labels.removeAll { $0 == id } }
            labels.removeValue(forKey: id)
            return .batch([.addLabel(previous)] + affected.map(TodoCommand.updateTask))
        case .addFilter(let filter):
            try insert(filter, into: &filters)
            return .removeRecord(kind: .filter, id: filter.id)
        case .renameFilter(let id, let name):
            let previous = try required(filters, id, .filter)
            filters[id]?.name = name
            return .renameFilter(id: id, name: previous.name)
        case .updateFilter(let filter):
            let previous = try required(filters, filter.id, .filter)
            filters[filter.id] = filter
            return .updateFilter(previous)
        case .deleteFilter(let id):
            let previous = try required(filters, id, .filter)
            filters.removeValue(forKey: id)
            return .addFilter(previous)
        case .addComment(let taskID, let comment):
            let previous = try required(tasks, taskID, .task)
            try validateID(comment.id)
            guard !previous.comments.contains(where: { $0.id == comment.id }) else {
                throw TodoCommandError.duplicateID(comment.id)
            }
            tasks[taskID]?.comments.append(comment)
            return .updateTask(previous)
        case .reorder(let kind, let orders):
            return try reorder(kind, orders: orders)
        case .removeRecord(let kind, let id):
            return try removeRecord(kind, id: id)
        case .batch(let commands):
            var inverses: [TodoCommand] = []
            for command in commands { inverses.append(try applyUnchecked(command)) }
            return .batch(inverses.reversed())
        }
    }

    private mutating func removeRecord(_ kind: TodoCommand.Entity, id: String) throws -> TodoCommand {
        switch kind {
        case .task:
            let previous = try required(tasks, id, kind)
            tasks.removeValue(forKey: id)
            return .addTask(previous)
        case .project:
            let previous = try required(projects, id, kind)
            projects.removeValue(forKey: id)
            return .addProject(previous)
        case .section:
            let previous = try required(sections, id, kind)
            sections.removeValue(forKey: id)
            return .addSection(previous)
        case .label:
            let previous = try required(labels, id, kind)
            labels.removeValue(forKey: id)
            return .addLabel(previous)
        case .filter:
            let previous = try required(filters, id, kind)
            filters.removeValue(forKey: id)
            return .addFilter(previous)
        }
    }

    private mutating func reorder(_ kind: TodoCommand.Entity, orders: [String: Int]) throws -> TodoCommand {
        var previous: [String: Int] = [:]
        for (id, order) in orders {
            switch kind {
            case .task:
                previous[id] = try required(tasks, id, kind).order
                tasks[id]?.order = order
            case .project:
                previous[id] = try required(projects, id, kind).order
                projects[id]?.order = order
            case .section:
                previous[id] = try required(sections, id, kind).order
                sections[id]?.order = order
            case .label:
                previous[id] = try required(labels, id, kind).order
                labels[id]?.order = order
            case .filter:
                previous[id] = try required(filters, id, kind).order
                filters[id]?.order = order
            }
        }
        return .reorder(kind: kind, orders: previous)
    }

    private func validate() throws {
        for section in sections.values { _ = try required(projects, section.projectID, .project) }
        for task in tasks.values { try validate(task) }
    }

    private func validate(_ task: TodoTask) throws {
        guard (1...4).contains(task.priority) else { throw TodoCommandError.invalidPriority(task.priority) }
        if let projectID = task.projectID { _ = try required(projects, projectID, .project) }
        if let sectionID = task.sectionID {
            let section = try required(sections, sectionID, .section)
            guard section.projectID == task.projectID else {
                throw TodoCommandError.sectionProjectMismatch(task.id)
            }
        }
        if let parentID = task.parentID {
            let parent = try required(tasks, parentID, .task)
            guard parent.projectID == task.projectID, parent.sectionID == task.sectionID else {
                throw TodoCommandError.parentLocationMismatch(task.id)
            }
        }
        var ancestors: Set<String> = [task.id]
        var parentID = task.parentID
        while let id = parentID {
            guard ancestors.insert(id).inserted else { throw TodoCommandError.parentCycle(id) }
            parentID = tasks[id]?.parentID
        }
        var seenLabels: Set<String> = []
        for id in task.labels {
            _ = try required(labels, id, .label)
            guard seenLabels.insert(id).inserted else { throw TodoCommandError.duplicateLabel(id) }
        }
        var seenComments: Set<String> = []
        for comment in task.comments {
            try validateID(comment.id)
            guard seenComments.insert(comment.id).inserted else { throw TodoCommandError.duplicateID(comment.id) }
        }
        if let due = task.due, due.isAllDay == (due.time != nil) {
            throw TodoCommandError.invalidDue(task.id)
        }
    }

    private func descendants(of id: String) -> [String] {
        var result = [id]
        var included: Set<String> = [id]
        var index = 0
        while index < result.count {
            let parentID = result[index]
            for task in tasks.values.sorted(by: { $0.id < $1.id })
                where task.parentID == parentID && included.insert(task.id).inserted {
                result.append(task.id)
            }
            index += 1
        }
        return result
    }

    private func required<Value>(_ values: [String: Value], _ id: String, _ kind: TodoCommand.Entity) throws -> Value {
        guard let value = values[id] else { throw TodoCommandError.unknownID(kind, id) }
        return value
    }

    private func validateID(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { throw TodoCommandError.invalidID(id) }
    }

    private func insert<Value: Identifiable>(_ value: Value, into values: inout [String: Value]) throws
        where Value.ID == String {
        try validateID(value.id)
        guard values[value.id] == nil else { throw TodoCommandError.duplicateID(value.id) }
        values[value.id] = value
    }
}
