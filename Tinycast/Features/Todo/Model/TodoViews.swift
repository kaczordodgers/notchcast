import Foundation

struct TodoViews: Sendable {
    let state: TodoState
    let now: Date
    let calendar: Calendar

    func inbox(options: TodoViewOptions = .init()) -> [TodoTaskGroup] {
        groups(visible(options).filter { $0.projectID == nil }, options: options)
    }

    func today(options: TodoViewOptions = .init()) -> [TodoTaskGroup] {
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        let tasks = visible(options).filter { task in task.due.map { $0.date < end } ?? false }
        return groups(tasks, options: options, today: true)
    }

    func upcoming(days: Int, options: TodoViewOptions = .init()) -> [TodoDayBucket] {
        guard days > 0 else { return [] }
        let start = calendar.startOfDay(for: now)
        let tasks = visible(options)
        let overdue = tasks.filter { task in task.due.map { $0.date < start } ?? false }
        var result = [TodoDayBucket(id: .overdue, groups: groups(overdue, options: options, today: true))]
        let byDay = Dictionary(grouping: tasks.filter { $0.due != nil }) { task in
            task.due.map { calendar.startOfDay(for: $0.date) }
        }
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            result.append(TodoDayBucket(id: .day(day), groups: groups(byDay[day] ?? [], options: options, today: true)))
        }
        return result
    }

    func project(id: String, options: TodoViewOptions = .init(grouping: .section)) -> [TodoTaskGroup] {
        guard state.projects[id] != nil else { return [] }
        let tasks = visible(options).filter { $0.projectID == id }
        var result = groups(tasks, options: options, nested: true)
        guard options.grouping == .section else { return result }
        let keys: [TodoTaskGroup.Key] = [.section(nil)] + orderedSections(projectID: id).map { .section($0.id) }
        let existing = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        result = keys.map { existing[$0] ?? TodoTaskGroup(id: $0, tasks: []) }
        return result
    }

    func label(name: String, options: TodoViewOptions = .init()) -> [TodoTaskGroup] {
        let ids = Set(state.labels.values.filter { $0.name.lowercased() == name.lowercased() }.map(\.id))
        return groups(visible(options).filter { !ids.isDisjoint(with: $0.labels) }, options: options)
    }

    private func visible(_ options: TodoViewOptions) -> [TodoTask] {
        state.tasks.values.filter { options.includeCompleted || $0.completedAt == nil }
    }

    private func groups(_ tasks: [TodoTask], options: TodoViewOptions,
                        nested: Bool = false, today: Bool = false) -> [TodoTaskGroup] {
        if options.grouping == .none {
            return [TodoTaskGroup(id: .all, tasks: nodes(tasks, options: options, nested: nested, today: today))]
        }
        var buckets: [TodoTaskGroup.Key: [TodoTask]] = [:]
        for task in tasks {
            for key in keys(for: task, grouping: options.grouping) { buckets[key, default: []].append(task) }
        }
        return buckets.keys.sorted(by: groupPrecedes).map { key in
            TodoTaskGroup(id: key, tasks: nodes(buckets[key] ?? [], options: options, nested: nested, today: today))
        }
    }

    private func keys(for task: TodoTask, grouping: TodoViewOptions.Grouping) -> [TodoTaskGroup.Key] {
        switch grouping {
        case .none: [.all]
        case .project: [.project(task.projectID)]
        case .section: [.section(task.sectionID)]
        case .priority: [.priority(task.priority)]
        case .dueDate: [.dueDate(task.due.map { calendar.startOfDay(for: $0.date) })]
        case .label: task.labels.isEmpty ? [.label(nil)] : task.labels.map { .label($0) }
        }
    }

    private func groupPrecedes(_ lhs: TodoTaskGroup.Key, _ rhs: TodoTaskGroup.Key) -> Bool {
        switch (lhs, rhs) {
        case (.priority(let left), .priority(let right)): return left > right
        case (.dueDate(let left), .dueDate(let right)):
            return optionalPrecedes(left, right)
        case (.project(let left), .project(let right)):
            return entityPrecedes(left, right) { state.projects[$0]?.order }
        case (.section(let left), .section(let right)):
            let leftProject = left.flatMap { state.sections[$0]?.projectID }
            let rightProject = right.flatMap { state.sections[$0]?.projectID }
            if leftProject != rightProject {
                return entityPrecedes(leftProject, rightProject) { state.projects[$0]?.order }
            }
            return entityPrecedes(left, right) { state.sections[$0]?.order }
        case (.label(let left), .label(let right)):
            return entityPrecedes(left, right) { state.labels[$0]?.order }
        default: return false
        }
    }

    private func entityPrecedes(_ lhs: String?, _ rhs: String?, order: (String) -> Int?) -> Bool {
        guard let lhs else { return rhs != nil }
        guard let rhs else { return false }
        let left = order(lhs) ?? 0
        let right = order(rhs) ?? 0
        return left == right ? lhs < rhs : left < right
    }

    private func orderedSections(projectID: String) -> [TodoSection] {
        state.sections.values.filter { $0.projectID == projectID }.sorted {
            $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }
    }

    private func nodes(_ tasks: [TodoTask], options: TodoViewOptions,
                       nested: Bool, today: Bool) -> [TodoTaskNode] {
        let ordered = sorted(tasks, by: options.sorting, today: today)
        guard nested else { return ordered.map { TodoTaskNode(task: $0) } }
        let ids = Set(tasks.map(\.id))
        let children = Dictionary(grouping: ordered, by: \.parentID)
        func node(_ task: TodoTask) -> TodoTaskNode {
            TodoTaskNode(task: task, subtasks: (children[task.id] ?? []).map(node))
        }
        return ordered.filter { $0.parentID.map { !ids.contains($0) } ?? true }.map(node)
    }

    private func sorted(_ tasks: [TodoTask], by sorting: TodoViewOptions.Sorting, today: Bool) -> [TodoTask] {
        tasks.sorted { lhs, rhs in
            if today {
                let start = calendar.startOfDay(for: now)
                let leftOverdue = lhs.due.map { $0.date < start } ?? false
                let rightOverdue = rhs.due.map { $0.date < start } ?? false
                if leftOverdue != rightOverdue { return leftOverdue }
            }
            switch sorting {
            case .manual where today, .due:
                let left = dueDate(lhs)
                let right = dueDate(rhs)
                if left != right { return optionalPrecedes(left, right) }
                if today, lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            case .priority:
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            case .name:
                let left = lhs.title.lowercased()
                let right = rhs.title.lowercased()
                if left != right { return left < right }
            case .added:
                if lhs.addedAt != rhs.addedAt { return optionalPrecedes(lhs.addedAt, rhs.addedAt) }
            case .manual: break
            }
            return lhs.order == rhs.order ? lhs.id < rhs.id : lhs.order < rhs.order
        }
    }

    private func dueDate(_ task: TodoTask) -> Date? {
        task.due.map { $0.isAllDay ? calendar.startOfDay(for: $0.date) : $0.date }
    }

    private func optionalPrecedes(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs else { return false }
        guard let rhs else { return true }
        return lhs < rhs
    }
}
