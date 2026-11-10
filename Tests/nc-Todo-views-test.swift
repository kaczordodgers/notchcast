// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
import Foundation

@main
struct TodoViewsTests {
    static func id(_ value: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", value)
    }

    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "Europe/Warsaw") else { preconditionFailure("missing time zone") }
        calendar.timeZone = zone
        return calendar
    }

    static func date(_ text: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: text) else { preconditionFailure("invalid fixture date") }
        return date
    }

    static func task(_ number: Int, _ title: String = "Task", due: Date? = nil, allDay: Bool = false,
                     priority: Int = 1, order: Int = 0) -> TodoTask {
        var task = TodoTask(id: id(number), title: title, priority: priority, order: order)
        if let due {
            task.due = .init(date: due, time: allDay ? nil : calendar().dateComponents([.hour, .minute], from: due),
                             isAllDay: allDay, normalized: "fixture")
        }
        return task
    }

    static func state(_ tasks: [TodoTask], commands: [TodoCommand] = []) throws -> TodoState {
        var state = TodoState()
        try state.apply(.batch(commands + tasks.map(TodoCommand.addTask)))
        return state
    }

    static func ids(_ groups: [TodoTaskGroup]) -> [String] {
        groups.flatMap(\.tasks).map(\.id)
    }

    static func main() throws {
        try today()
        try daylightSaving()
        try upcoming()
        try projectAndDetail()
        try options()
        try deterministicOrdering()
        try workflow()
        print("PASS: Today, midnight/DST, Upcoming, project trees, detail, every group/sort and workflow idempotence")
    }

    static func today() throws {
        let now = date("2027-03-28T00:15:00+01:00")
        let yesterday = task(1, due: date("2027-03-27T23:59:59+01:00"), priority: 1)
        let old = task(2, due: date("2027-03-26T23:00:00+01:00"), priority: 4)
        let allDay = task(3, due: date("2027-03-28T12:00:00+02:00"), allDay: true)
        let late = task(4, due: date("2027-03-28T23:59:59+02:00"), priority: 4)
        let early = task(5, due: date("2027-03-28T08:00:00+02:00"), priority: 1)
        let urgent = task(6, due: early.due?.date, priority: 4, order: 9)
        let firstUrgent = task(7, due: early.due?.date, priority: 4, order: 2)
        let tomorrow = task(8, due: date("2027-03-29T00:00:00+02:00"))
        var done = task(9, due: old.due?.date)
        done.completedAt = now
        let state = try state([yesterday, old, allDay, late, early, urgent, firstUrgent, tomorrow, done, task(10)])
        let views = TodoViews(state: state, now: now, calendar: calendar())
        precondition(ids(views.today()) == [2, 1, 3, 7, 6, 5, 4].map(id))
        precondition(ids(views.today(options: .init(includeCompleted: true))).contains(done.id))
        let nextDay = TodoViews(state: state, now: date("2027-03-29T00:00:00+02:00"), calendar: calendar())
        precondition(ids(nextDay.today()).last == tomorrow.id)
        let beforeMidnight = TodoViews(state: state, now: date("2027-03-27T23:59:58+01:00"), calendar: calendar())
        precondition(ids(beforeMidnight.today()) == [old.id, yesterday.id])
        precondition(state.tasks.count == 10)
        print("PASS: Today overdue first, due time, priority 4 to 1, manual ties and midnight rollover")
    }

    static func daylightSaving() throws {
        for (text, hours) in [("2027-03-28T00:00:00+01:00", 23), ("2027-10-31T00:00:00+02:00", 25)] {
            let start = date(text)
            guard let next = calendar().date(byAdding: .day, value: 1, to: start) else {
                preconditionFailure("missing next day")
            }
            precondition(next.timeIntervalSince(start) == Double(hours * 3600))
            let before = task(1, due: start.addingTimeInterval(-1))
            let first = task(2, due: start)
            let last = task(3, due: next.addingTimeInterval(-1))
            let after = task(4, due: next)
            let views = TodoViews(state: try state([before, first, last, after]), now: start, calendar: calendar())
            precondition(ids(views.today()) == [before.id, first.id, last.id])
            let buckets = views.upcoming(days: 2)
            precondition(buckets.map(\.id) == [.overdue, .day(start), .day(next)])
            precondition(ids(buckets[1].groups) == [first.id, last.id])
            precondition(ids(buckets[2].groups) == [after.id])
        }
        let first = task(1, due: date("2027-10-31T02:30:00+02:00"))
        let second = task(2, due: date("2027-10-31T02:30:00+01:00"))
        let views = TodoViews(state: try state([second, first]), now: date("2027-10-31T12:00:00+01:00"),
                              calendar: calendar())
        precondition(ids(views.today()) == [first.id, second.id])
        print("PASS: 23/25-hour days and both occurrences of the repeated DST hour")
    }

    static func upcoming() throws {
        let now = date("2027-03-28T12:00:00+02:00")
        let before = task(1, due: date("2027-03-27T12:00:00+01:00"))
        let later = task(2, due: date("2027-03-30T12:00:00+02:00"))
        let outside = task(3, due: date("2027-03-31T00:00:00+02:00"))
        var done = task(4, due: now)
        done.completedAt = now
        let views = TodoViews(state: try state([before, later, outside, done, task(5)]), now: now, calendar: calendar())
        let buckets = views.upcoming(days: 3)
        precondition(buckets.count == 4 && buckets[0].id == .overdue)
        precondition(ids(buckets[0].groups) == [before.id])
        precondition(ids(buckets[1].groups).isEmpty && ids(buckets[2].groups).isEmpty)
        precondition(ids(buckets[3].groups) == [later.id])
        precondition(views.upcoming(days: 0).isEmpty && views.upcoming(days: -1).isEmpty)
        precondition(ids(views.upcoming(days: 1, options: .init(includeCompleted: true))[1].groups) == [done.id])
        let empty = TodoViews(state: TodoState(), now: now, calendar: calendar()).upcoming(days: 2)
        precondition(empty.count == 3 && empty.allSatisfy { ids($0.groups).isEmpty })
        print("PASS: Upcoming retains empty days and overdue bucket; bounds and completion filter")
    }

    static func projectAndDetail() throws {
        let project = TodoProject(id: id(100), name: "Work")
        let early = TodoSection(id: id(101), name: "Early", projectID: project.id, order: 1)
        let late = TodoSection(id: id(102), name: "Late", projectID: project.id, order: 9)
        let empty = TodoSection(id: id(103), name: "Empty", projectID: project.id, order: 10)
        var root = task(1, "Root", order: 9)
        root.projectID = project.id
        root.description = "**Markdown**"
        let now = date("2027-04-01T12:00:00+02:00")
        let firstComment = TodoComment(id: id(201), text: "First", createdAt: now)
        let secondComment = TodoComment(id: id(200), text: "Second", createdAt: now)
        let lastComment = TodoComment(id: id(202), text: "Last", createdAt: now.addingTimeInterval(1))
        root.comments = [lastComment, firstComment, secondComment]
        var child = task(2, "Child", order: 0)
        child.projectID = project.id
        child.parentID = root.id
        let grandchild = TodoTask(id: id(3), title: "Grandchild", projectID: project.id, parentID: child.id)
        var sectionTask = task(4)
        sectionTask.projectID = project.id
        sectionTask.sectionID = early.id
        var lateTask = task(5)
        lateTask.projectID = project.id
        lateTask.sectionID = late.id
        let initial = try state([lateTask, grandchild, child, root, sectionTask], commands:
            [.addProject(project), .addSection(late), .addSection(empty), .addSection(early)])
        let views = TodoViews(state: initial, now: now, calendar: calendar())
        let groups = views.project(id: project.id)
        precondition(groups.map(\.id) == [.section(nil), .section(early.id), .section(late.id), .section(empty.id)])
        precondition(groups[0].tasks.count == 1 && groups[0].tasks[0].id == root.id)
        precondition(groups[0].tasks[0].subtasks[0].id == child.id)
        precondition(groups[0].tasks[0].subtasks[0].subtasks[0].id == grandchild.id)
        precondition(groups[3].tasks.isEmpty && views.project(id: id(999)).isEmpty)
        guard let detail = TodoTaskDetail(id: child.id, state: initial),
              let rootDetail = TodoTaskDetail(id: root.id, state: initial) else { preconditionFailure("missing detail") }
        precondition(detail.ancestors.map(\.id) == [root.id] && detail.subtasks.map(\.id) == [grandchild.id])
        precondition(TodoTaskDetail(id: grandchild.id, state: initial)?.ancestors.map(\.id) == [root.id, child.id])
        precondition(rootDetail.task.description == "**Markdown**")
        precondition(rootDetail.comments == [firstComment, secondComment, lastComment])
        precondition(TodoTaskDetail(id: id(999), state: initial) == nil)
        var completed = initial
        try completed.apply(.completeTask(id: child.id, at: now))
        let filtered = TodoViews(state: completed, now: now, calendar: calendar())
        precondition(filtered.project(id: project.id)[0].tasks.map(\.id) == [grandchild.id, root.id])
        precondition(TodoTaskDetail(id: root.id, state: completed)?.subtasks.map(\.id) == [grandchild.id])
        precondition(TodoTaskDetail(id: root.id, state: completed, includeCompleted: true)?.subtasks[0].id == child.id)
        print("PASS: project section order, nested subtasks, visible descendants and chronological detail comments")
    }

    static func options() throws {
        let now = date("2027-04-01T12:00:00+02:00")
        let project = TodoProject(id: id(100), name: "Project")
        let section = TodoSection(id: id(101), name: "Section", projectID: project.id)
        let focus = TodoLabel(id: id(102), name: "Focus")
        let extra = TodoLabel(id: id(103), name: "Extra", order: -1)
        var alpha = task(1, "alpha", due: now, priority: 2, order: 2)
        alpha.labels = [focus.id, extra.id]
        alpha.addedAt = now.addingTimeInterval(-1)
        var beta = task(2, "Beta", due: now.addingTimeInterval(3600), priority: 4, order: 1)
        beta.labels = [focus.id]
        beta.projectID = project.id
        beta.sectionID = section.id
        beta.addedAt = now.addingTimeInterval(-2)
        var gamma = task(3, "gamma", priority: 1, order: 0)
        gamma.labels = [focus.id]
        let initial = try state([alpha, beta, gamma], commands:
            [.addProject(project), .addSection(section), .addLabel(focus), .addLabel(extra)])
        let views = TodoViews(state: initial, now: now, calendar: calendar())
        let expected: [TodoViewOptions.Sorting: [String]] = [
            .manual: [gamma.id, beta.id, alpha.id], .due: [alpha.id, beta.id, gamma.id],
            .priority: [beta.id, alpha.id, gamma.id], .name: [alpha.id, beta.id, gamma.id],
            .added: [beta.id, alpha.id, gamma.id]
        ]
        for sorting in TodoViewOptions.Sorting.allCases {
            precondition(ids(views.label(name: "FOCUS", options: .init(sorting: sorting))) == expected[sorting])
        }
        let keys: [TodoViewOptions.Grouping: [TodoTaskGroup.Key]] = [
            .none: [.all], .project: [.project(nil), .project(project.id)],
            .section: [.section(nil), .section(section.id)], .priority: [.priority(4), .priority(2), .priority(1)],
            .dueDate: [.dueDate(calendar().startOfDay(for: now)), .dueDate(nil)],
            .label: [.label(extra.id), .label(focus.id)]
        ]
        for grouping in TodoViewOptions.Grouping.allCases {
            let groups = views.label(name: "focus", options: .init(grouping: grouping))
            precondition(groups.map(\.id) == keys[grouping])
            precondition(Set(ids(groups)) == Set([alpha.id, beta.id, gamma.id]))
            for sorting in TodoViewOptions.Sorting.allCases {
                let options = TodoViewOptions(grouping: grouping, sorting: sorting, includeCompleted: true)
                let saved = ["inbox": options, "project:\(project.id)": options]
                let decoded = try JSONDecoder().decode([String: TodoViewOptions].self, from: JSONEncoder().encode(saved))
                precondition(decoded == saved)
                precondition(!views.inbox(options: options).isEmpty)
                precondition(!views.today(options: options).isEmpty)
                precondition(!views.project(id: project.id, options: options).isEmpty)
                let upcoming = views.upcoming(days: 1, options: options)
                precondition(upcoming[1].groups.map(\.id) == views.today(options: options).map(\.id))
            }
        }
        precondition(ids(views.label(name: "unknown")).isEmpty)
        precondition(ids(views.inbox()) == [gamma.id, alpha.id])
        let unlabelled = TodoViews(state: try state([task(4)]), now: now, calendar: calendar())
        precondition(unlabelled.inbox(options: .init(grouping: .label)).map(\.id) == [.label(nil)])
        let encoded = try JSONEncoder().encode(alpha)
        guard var legacy = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            preconditionFailure("invalid task encoding")
        }
        legacy.removeValue(forKey: "addedAt")
        let decoded = try JSONDecoder().decode(TodoTask.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(decoded.addedAt == nil)
        print("PASS: all 6 grouping and 5 sorting choices, per-view Codable options, label lookup and legacy addedAt")
    }

    static func deterministicOrdering() throws {
        let now = date("2027-04-01T12:00:00+02:00")
        let lateProject = TodoProject(id: id(100), name: "Late", order: 10)
        let earlyProject = TodoProject(id: id(101), name: "Early", order: -10)
        let lateSection = TodoSection(id: id(102), name: "Late", projectID: lateProject.id, order: -10)
        let earlySection = TodoSection(id: id(103), name: "Early", projectID: earlyProject.id, order: 10)
        let label = TodoLabel(id: id(104), name: "All")
        var late = task(2, "Same", due: now, order: 1)
        late.labels = [label.id]
        late.projectID = lateProject.id
        late.sectionID = lateSection.id
        var early = TodoTask(id: id(1), title: late.title, projectID: earlyProject.id, sectionID: earlySection.id,
                             due: late.due, labels: late.labels, order: late.order)
        early.addedAt = late.addedAt
        let commands: [TodoCommand] = [.addProject(lateProject), .addProject(earlyProject),
                                      .addSection(lateSection), .addSection(earlySection), .addLabel(label)]
        let first = TodoViews(state: try state([late, early], commands: commands), now: now, calendar: calendar())
        let second = TodoViews(state: try state([early, late], commands: commands), now: now, calendar: calendar())
        for sorting in TodoViewOptions.Sorting.allCases {
            let options = TodoViewOptions(sorting: sorting)
            precondition(ids(first.label(name: "All", options: options)) == [early.id, late.id])
            precondition(first.label(name: "All", options: options) == second.label(name: "All", options: options))
        }
        precondition(first.label(name: "All", options: .init(grouping: .project)).map(\.id)
                     == [.project(earlyProject.id), .project(lateProject.id)])
        precondition(first.label(name: "All", options: .init(grouping: .section)).map(\.id)
                     == [.section(earlySection.id), .section(lateSection.id)])
        var completed = first.state
        try completed.apply(.completeTask(id: early.id, at: now))
        let views = TodoViews(state: completed, now: now, calendar: calendar())
        precondition(ids(views.label(name: "All")) == [late.id])
        precondition(ids(views.project(id: earlyProject.id)).isEmpty)
        precondition(ids(views.project(id: earlyProject.id, options: .init(includeCompleted: true))) == [early.id])
        print("PASS: stable UUID sort ties, cross-project section order and project/label completion filtering")
    }

    static func workflow() throws {
        let project = TodoProject(id: id(100), name: "Work")
        let other = TodoProject(id: id(101), name: "Other")
        let backlog = TodoSection(id: id(102), name: "BACKLOG", projectID: project.id, order: 20)
        let elsewhere = TodoSection(id: id(103), name: "Up next", projectID: other.id)
        let initial = try state([], commands: [.addProject(project), .addProject(other),
                                                .addSection(backlog), .addSection(elsewhere)])
        var state = initial
        var nextID = 200
        guard let command = try state.workflowSectionsCommand(projectID: project.id, makeID: {
            nextID += 1
            return id(nextID)
        }) else { preconditionFailure("missing workflow command") }
        let inverse = try state.apply(command)
        precondition(state.sections.count == 6 && state.sections[backlog.id] == backlog)
        let names = state.sections.values.filter { $0.projectID == project.id }
            .sorted { $0.order < $1.order }.map { $0.name.lowercased() }
        precondition(names == ["backlog", "up next", "in progress", "blocked", "someday"])
        let noChange = try state.workflowSectionsCommand(projectID: project.id, makeID: {
            preconditionFailure("idempotent call requested an ID")
        })
        precondition(noChange == nil)
        try state.apply(inverse)
        precondition(state == initial)
        do {
            _ = try state.workflowSectionsCommand(projectID: id(999), makeID: { id(300) })
            preconditionFailure("accepted missing project")
        } catch let error as TodoCommandError { precondition(error == .unknownID(.project, id(999))) }
        var fullOrder = initial
        try fullOrder.apply(.reorder(kind: .section, orders: [backlog.id: Int.max]))
        let before = fullOrder
        let compact = try fullOrder.workflowSectionsCommand(projectID: project.id, makeID: {
            nextID += 1
            return id(nextID)
        })
        guard let compact else { preconditionFailure("missing overflow plan") }
        let undo = try fullOrder.apply(compact)
        try fullOrder.apply(undo)
        precondition(fullOrder == before)
        print("PASS: workflow case-insensitive/project-local idempotence, atomic undo and order overflow")
    }
}
