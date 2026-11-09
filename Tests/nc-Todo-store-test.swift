// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/*.swift Tinycast/Features/Todo/TodoModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import Foundation

@main @MainActor
struct TodoStoreTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let project = TodoProject(id: UUID().uuidString, name: "Work")
    static let otherProject = TodoProject(id: UUID().uuidString, name: "Home")
    static let section = TodoSection(id: UUID().uuidString, name: "Up next", projectID: project.id)
    static let otherSection = TodoSection(id: UUID().uuidString, name: "Backlog", projectID: otherProject.id)
    static let label = TodoLabel(id: UUID().uuidString, name: "Focus")
    static let filter = TodoSavedFilter(id: UUID().uuidString, name: "Urgent", query: "p1")
    static let task = TodoTask(id: UUID().uuidString, title: "Ship", description: "**Markdown**",
                               projectID: project.id, sectionID: section.id, priority: 4,
                               due: .init(date: now, isAllDay: true, normalized: "2027-01-15"),
                               labels: [label.id], externalRef: "imported-task")
    static let child = TodoTask(id: UUID().uuidString, title: "Review", projectID: project.id,
                                sectionID: section.id, parentID: task.id)
    static let comment = TodoComment(id: UUID().uuidString, text: "Checkpoint", createdAt: now)

    static func main() async throws {
        try commands()
        try rejections()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await persistence(root.appending(path: "replay"))
        try await tornLine(root.appending(path: "torn"))
        try await corruptLines(root.appending(path: "corrupt"))
        try await lifecycle(root.appending(path: "module"))
        try await performance(root.appending(path: "performance"))
        print("PASS: every command/inverse, undo chain, atomic rejection, replay, torn tail, schema and lifecycle")
    }

    static func fixture() throws -> TodoState {
        var state = TodoState()
        try state.apply(.batch([.addProject(project), .addProject(otherProject), .addSection(section),
                                .addSection(otherSection), .addLabel(label), .addFilter(filter),
                                .addTask(task), .addTask(child)]))
        return state
    }

    static func commands() throws {
        let initial = try fixture()
        precondition(initial.sections.count == 2)
        precondition(TodoState().sections.isEmpty)
        precondition(task.priority == 4 && child.priority == 1)
        var edited = task
        edited.title = "Ship today"
        edited.description = "# Updated"
        edited.due = .init(date: now, time: DateComponents(hour: 9, minute: 30), isAllDay: false,
                           recurrenceRule: "FREQ=WEEKLY", normalized: "every Friday at 09:30")
        var editedFilter = filter
        editedFilter.query = "p1 & today"
        var commands: [TodoCommand] = [
            .addTask(.init(id: UUID().uuidString, title: "Inbox")), .updateTask(edited),
            .moveTask(id: task.id, projectID: otherProject.id, sectionID: otherSection.id, parentID: nil),
            .completeTask(id: task.id, at: now), .uncompleteTask(id: task.id), .deleteTask(id: task.id),
            .addProject(.init(id: UUID().uuidString, name: "New")), .renameProject(id: project.id, name: "Renamed"),
            .deleteProject(id: project.id),
            .addSection(.init(id: UUID().uuidString, name: "New", projectID: project.id)),
            .renameSection(id: section.id, name: "In progress"), .deleteSection(id: section.id),
            .addLabel(.init(id: UUID().uuidString, name: "New")), .renameLabel(id: label.id, name: "Renamed"),
            .deleteLabel(id: label.id), .addFilter(.init(id: UUID().uuidString, name: "New", query: "today")),
            .renameFilter(id: filter.id, name: "Renamed"), .updateFilter(editedFilter), .deleteFilter(id: filter.id),
            .addComment(taskID: task.id, comment: comment), .batch([.updateTask(edited), .addComment(taskID: task.id,
                                                                                                 comment: comment)]),
            .removeRecord(kind: .task, id: child.id)
        ]
        let orders: [(TodoCommand.Entity, String)] = [(.task, task.id), (.project, project.id),
                                                     (.section, section.id), (.label, label.id), (.filter, filter.id)]
        commands += orders.map { .reorder(kind: $0.0, orders: [$0.1: 8]) }
        for command in commands {
            var state = initial
            let inverse = try state.apply(command)
            let changed = state
            let redo = try state.apply(inverse)
            precondition(state == initial, "inverse failed for \(command)")
            try state.apply(redo)
            precondition(state == changed)
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(TodoCommand.self, from: encoded)
            precondition(decoded == command)
        }
        var state = initial
        try state.apply(.completeTask(id: task.id, at: now))
        precondition(state.tasks[task.id]?.completedAt == now)
        let inverse = try state.apply(.uncompleteTask(id: task.id))
        precondition(state.tasks[task.id]?.completedAt == nil)
        try state.apply(inverse)
        precondition(state.tasks[task.id]?.completedAt == now)
        try state.apply(.moveTask(id: task.id, projectID: otherProject.id, sectionID: otherSection.id, parentID: nil))
        precondition(state.tasks[child.id]?.projectID == otherProject.id)
        precondition(state.tasks[child.id]?.sectionID == otherSection.id)
        precondition(state.tasks[child.id]?.parentID == task.id)
        var deleting = initial
        try deleting.apply(.deleteTask(id: task.id))
        precondition(deleting.tasks.isEmpty)
        deleting = initial
        try deleting.apply(.deleteProject(id: project.id))
        precondition(deleting.tasks.isEmpty && deleting.sections[section.id] == nil)
        deleting = initial
        try deleting.apply(.deleteSection(id: section.id))
        precondition(deleting.tasks.count == 2 && deleting.tasks.values.allSatisfy { $0.sectionID == nil })
        deleting = initial
        try deleting.apply(.deleteLabel(id: label.id))
        precondition(deleting.tasks[task.id]?.labels.isEmpty == true)
        var reversedInsertion = initial
        try reversedInsertion.apply(.deleteTask(id: task.id))
        let empty = reversedInsertion
        let inverseInsertion = try reversedInsertion.apply(.batch([.addTask(child), .addTask(task)]))
        let redoInsertion = try reversedInsertion.apply(inverseInsertion)
        precondition(reversedInsertion == empty)
        try reversedInsertion.apply(redoInsertion)
        precondition(reversedInsertion == initial)
        var projectLast = TodoState()
        let referencingTask = TodoTask(id: task.id, title: "Project added last", projectID: project.id)
        let inverseProjectLast = try projectLast.apply(.batch([.addTask(referencingTask), .addProject(project)]))
        let redoProjectLast = try projectLast.apply(inverseProjectLast)
        precondition(projectLast == TodoState())
        try projectLast.apply(redoProjectLast)
        precondition(projectLast.tasks[task.id] == referencingTask && projectLast.projects[project.id] == project)
        print("PASS: 27 command variants round-trip through inverse, redo and Codable")
    }

    static func reject(_ command: TodoCommand, in initial: TodoState, matching expected: TodoCommandError) throws {
        var state = initial
        do {
            try state.apply(command)
            preconditionFailure("accepted invalid command: \(command)")
        } catch let error as TodoCommandError {
            precondition(error == expected, "wrong error: \(error), expected \(expected)")
        }
        precondition(state == initial, "rejected command mutated the state")
    }

    static func rejections() throws {
        let initial = try fixture()
        let missing = UUID().uuidString
        try reject(.deleteTask(id: missing), in: initial, matching: .unknownID(.task, missing))
        try reject(.addTask(task), in: initial, matching: .duplicateID(task.id))
        try reject(.addTask(.init(id: "untrusted", title: "Bad")), in: initial, matching: .invalidID("untrusted"))
        for priority in [0, 5] {
            var invalid = task
            invalid.priority = priority
            try reject(.updateTask(invalid), in: initial, matching: .invalidPriority(priority))
        }
        try reject(.moveTask(id: task.id, projectID: project.id, sectionID: section.id, parentID: task.id),
                   in: initial, matching: .parentCycle(task.id))
        var cycle = TodoState()
        let selfParent = TodoTask(id: task.id, title: "Cycle", parentID: task.id)
        try reject(.addTask(selfParent), in: cycle, matching: .parentCycle(task.id))
        let first = TodoTask(id: task.id, title: "A", parentID: child.id)
        let second = TodoTask(id: child.id, title: "B", parentID: task.id)
        do {
            try cycle.apply(.batch([.addTask(first), .addTask(second)]))
            preconditionFailure("accepted a two-node cycle")
        } catch let error as TodoCommandError {
            guard case .parentCycle = error else { preconditionFailure("wrong cycle error") }
        }
        precondition(cycle == TodoState())
        try reject(.moveTask(id: task.id, projectID: otherProject.id, sectionID: section.id, parentID: nil),
                   in: initial, matching: .sectionProjectMismatch(task.id))
        var wrongProject = task
        wrongProject.projectID = missing
        wrongProject.sectionID = nil
        var single = TodoState()
        try single.apply(.addLabel(label))
        try reject(.addTask(wrongProject), in: single, matching: .unknownID(.project, missing))
        var missingParent = task
        missingParent.parentID = missing
        try reject(.updateTask(missingParent), in: initial, matching: .unknownID(.task, missing))
        var mismatched = child
        mismatched.projectID = otherProject.id
        mismatched.sectionID = otherSection.id
        try reject(.updateTask(mismatched), in: initial, matching: .parentLocationMismatch(child.id))
        var badLabels = task
        badLabels.labels = [missing]
        try reject(.updateTask(badLabels), in: initial, matching: .unknownID(.label, missing))
        badLabels.labels = [label.id, label.id]
        try reject(.updateTask(badLabels), in: initial, matching: .duplicateLabel(label.id))
        var badDue = task
        badDue.due?.isAllDay = false
        try reject(.updateTask(badDue), in: initial, matching: .invalidDue(task.id))
        var withComment = initial
        try withComment.apply(.addComment(taskID: task.id, comment: comment))
        try reject(.addComment(taskID: task.id, comment: comment), in: withComment, matching: .duplicateID(comment.id))
        try reject(.batch([.renameProject(id: project.id, name: "Changed"), .deleteTask(id: missing)]),
                   in: initial, matching: .unknownID(.task, missing))
        try reject(.reorder(kind: .task, orders: [task.id: 8, missing: 9]), in: initial,
                   matching: .unknownID(.task, missing))
        for kind in [TodoCommand.Entity.project, .section, .label, .filter] {
            try reject(.reorder(kind: kind, orders: [missing: 8]), in: initial, matching: .unknownID(kind, missing))
        }
        let unknownCommands: [(TodoCommand, TodoCommand.Entity)] = [
            (.updateTask(.init(id: missing, title: "Missing")), .task),
            (.completeTask(id: missing, at: now), .task), (.uncompleteTask(id: missing), .task),
            (.moveTask(id: missing, projectID: nil, sectionID: nil, parentID: nil), .task),
            (.addComment(taskID: missing, comment: comment), .task),
            (.renameProject(id: missing, name: "Missing"), .project), (.deleteProject(id: missing), .project),
            (.renameSection(id: missing, name: "Missing"), .section), (.deleteSection(id: missing), .section),
            (.renameLabel(id: missing, name: "Missing"), .label), (.deleteLabel(id: missing), .label),
            (.renameFilter(id: missing, name: "Missing"), .filter), (.deleteFilter(id: missing), .filter),
            (.updateFilter(.init(id: missing, name: "Missing", query: "today")), .filter)
        ]
        for (command, kind) in unknownCommands {
            try reject(command, in: initial, matching: .unknownID(kind, missing))
        }
        try reject(.addSection(.init(id: missing, name: "Missing", projectID: missing)),
                   in: initial, matching: .unknownID(.project, missing))
        for kind in [TodoCommand.Entity.task, .project, .section, .label, .filter] {
            try reject(.removeRecord(kind: kind, id: missing), in: initial, matching: .unknownID(kind, missing))
        }
    }

    static func persistence(_ directory: URL) async throws {
        let store = try await TodoStore.open(directory: directory)
        precondition(store.state == TodoState() && !store.canUndo)
        let commands: [TodoCommand] = [.addProject(project), .addSection(section), .addLabel(label),
                                       .addTask(task), .addTask(child), .addComment(taskID: task.id, comment: comment),
                                       .completeTask(id: task.id, at: now), .deleteProject(id: project.id)]
        var states = [store.state]
        for command in commands { try store.perform(command); states.append(store.state) }
        try store.close()
        let restored = try await TodoStore.open(directory: directory)
        precondition(restored.state == states.last && restored.canUndo)
        for expected in states.dropLast().reversed() {
            try restored.undo()
            precondition(restored.state == expected)
        }
        precondition(!restored.canUndo)
        do { try restored.undo(); preconditionFailure("empty undo succeeded") } catch TodoStore.Failure.noUndo { }
        try restored.perform(.addTask(.init(id: UUID().uuidString, title: "After undo")))
        let expected = restored.state
        let logURL = directory.appending(path: "commands.jsonl")
        let bytes = try Data(contentsOf: logURL)
        do {
            try restored.perform(.deleteTask(id: UUID().uuidString))
            preconditionFailure("invalid perform succeeded")
        } catch is TodoCommandError { }
        let unchanged = try Data(contentsOf: logURL)
        precondition(unchanged == bytes && restored.state == expected)
        try restored.close()
        let replayed = try await TodoStore.open(directory: directory)
        precondition(replayed.state == expected && replayed.canUndo)
        try replayed.undo()
        precondition(replayed.state == TodoState())
        try replayed.close()
        do {
            try replayed.perform(.addProject(project))
            preconditionFailure("closed write succeeded")
        } catch TodoStore.Failure.closed { }
    }

    static func tornLine(_ directory: URL) async throws {
        let store = try await TodoStore.open(directory: directory)
        try store.perform(.addProject(project))
        let expected = store.state
        try store.close()
        let url = directory.appending(path: "commands.jsonl")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"schemaVersion\":1,\"command\":".utf8))
        try handle.close()
        let recovered = try await TodoStore.open(directory: directory)
        precondition(recovered.state == expected && recovered.loadWarnings == [.tornLastLine(line: 2)])
        try recovered.perform(.addLabel(label))
        let after = recovered.state
        try recovered.close()
        let reloaded = try await TodoStore.open(directory: directory)
        precondition(reloaded.loadWarnings.isEmpty && reloaded.state == after)
        try reloaded.close()
    }

    static func corruptLines(_ directory: URL) async throws {
        let store = try await TodoStore.open(directory: directory)
        try store.perform(.addProject(project))
        try store.close()
        let url = directory.appending(path: "commands.jsonl")
        let original = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: original)
        guard var record = object as? [String: Any] else { preconditionFailure("not a record") }
        record["schemaVersion"] = 99
        var future = try JSONSerialization.data(withJSONObject: record)
        future.append(0x0A)
        try future.write(to: url)
        do {
            _ = try await TodoStore.open(directory: directory)
            preconditionFailure("future schema loaded")
        } catch TodoStore.Failure.unsupportedSchema(99) { }
        let intact = try Data(contentsOf: url)
        precondition(intact == future)
        try Data("not JSON\n".utf8).write(to: url)
        do {
            _ = try await TodoStore.open(directory: directory)
            preconditionFailure("corrupt line loaded")
        } catch TodoStore.Failure.corruptLine(1) { }
    }

    static func lifecycle(_ directory: URL) async throws {
        let suite = "todo-module.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.tasks) && !NotchcastFeature.tasks.needsIsland)
        precondition(NotchcastFeature.tasks.dependencies.isEmpty && NotchcastFeature.tasks.requiredGrants.isEmpty)
        precondition(NotchcastFeature.tasks.settingsGroup == .tasks)
        var failures: [String] = []
        let module = TodoModule(directory: directory, showFailure: { failures.append($0) })
        let controller = NotchcastModuleController([.init(requires: [.tasks], module: module)], preferences: preferences)
        controller.run()
        precondition(module.store == nil && !FileManager.default.fileExists(atPath: directory.path))
        preferences.set(.island, false)
        preferences.set(.tasks, true)
        for _ in 0..<200 where module.store == nil { try await Task.sleep(for: .milliseconds(5)) }
        guard let opened = module.store else { preconditionFailure("module did not load") }
        try opened.perform(.addProject(project))
        preferences.set(.tasks, false)
        for _ in 0..<50 where module.store != nil { await Task.yield() }
        precondition(module.store == nil)
        do {
            try opened.perform(.addLabel(label))
            preconditionFailure("disabled store wrote")
        } catch TodoStore.Failure.closed { }
        preferences.set(.tasks, true)
        for _ in 0..<200 where module.store == nil { try await Task.sleep(for: .milliseconds(5)) }
        precondition(module.store?.state.projects[project.id] == project)
        module.stop()
        module.start()
        module.stop()
        try await Task.sleep(for: .milliseconds(25))
        precondition(module.store == nil && failures.isEmpty)
    }

    static func performance(_ directory: URL) async throws {
        let store = try await TodoStore.open(directory: directory)
        for index in 0..<1000 {
            try store.perform(.addTask(.init(id: UUID().uuidString, title: "Task \(index)")))
        }
        let expected = store.state
        try store.close()
        let start = ContinuousClock.now
        let reloaded = try await TodoStore.open(directory: directory)
        let elapsed = start.duration(to: .now)
        precondition(reloaded.state == expected && reloaded.state.tasks.count == 1000)
        try reloaded.close()
        print("PASS: 1000-command reload \(elapsed)")
    }
}
