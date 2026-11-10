// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: -O Tinycast/Features/Todo/Service/TodoStore.swift
import Foundation

@main @MainActor
struct TodoSyncTests {
    static func precondition(_ condition: @autoclosure () -> Bool,
                             _ message: @autoclosure () -> String = "",
                             file: StaticString = #file, line: UInt = #line) {
        if !condition() { preconditionFailure(message(), file: file, line: line) }
    }

    static func preconditionFailure(_ message: @autoclosure () -> String = "",
                                    file: StaticString = #file, line: UInt = #line) -> Never {
        let reason = "\(file):\(line): Precondition failed: \(message()) (SIGTRAP, signal 5)\n"
        FileHandle.standardError.write(Data(reason.utf8))
        fatalError(reason, file: file, line: line)
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let project = TodoProject(id: UUID().uuidString, name: "Work")
    static let backlog = TodoSection(id: UUID().uuidString, name: "Backlog", projectID: project.id)
    static let progress = TodoSection(id: UUID().uuidString, name: "In progress", projectID: project.id)
    static let blocked = TodoSection(id: UUID().uuidString, name: "Blocked", projectID: project.id)
    static let label = TodoLabel(id: UUID().uuidString, name: "focus")
    static let otherLabel = TodoLabel(id: UUID().uuidString, name: "review")
    static let task = TodoTask(id: UUID().uuidString, title: "Ship", projectID: project.id,
                               sectionID: backlog.id, priority: 4)

    static func main() async throws {
        try convergence()
        try fields()
        try deletion()
        try replay()
        try relationships()
        try vectors()
        try agents()
        try agentFailures()
        try reviewRegressions()
        try clockQuarantine()
        try json()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await persistence(root)
        try await quarantinePersistence(root.appending(path: "quarantine"))
        try await performance(root.appending(path: "performance"))
        print("PASS: sync convergence, per-field LWW, deletes, duplicates, vectors, fake transport, legacy log, agents, JSON")
    }

    static func fixture() throws -> TodoReplication {
        var value = TodoReplication(replicaID: "seed")
        try value.perform(.batch([.addProject(project), .addSection(backlog), .addSection(progress),
                                  .addSection(blocked), .addLabel(label), .addLabel(otherLabel), .addTask(task)]))
        return value
    }

    static func replica(_ id: String) throws -> TodoReplication {
        try TodoReplication.merge(local: TodoReplication(replicaID: id), remote: fixture().envelopes, now: now)
    }

    static func converged(_ left: TodoReplication, _ right: TodoReplication) throws -> TodoReplication {
        let first = try TodoReplication.merge(local: left, remote: right.envelopes.reversed(), now: now)
        let second = try TodoReplication.merge(local: right, remote: left.envelopes.reversed(), now: now)
        precondition(first.state == second.state)
        precondition(first.envelopes == second.envelopes)
        precondition(first.vectorClock == second.vectorClock)
        precondition(first.orphansRecovered == second.orphansRecovered)
        let again = try TodoReplication.merge(local: first, remote: first.envelopes + right.envelopes, now: now)
        precondition(again.state == first.state && again.envelopes == first.envelopes)
        return first
    }

    static func convergence() throws {
        var left = try replica("a")
        var right = try replica("b")
        var title = task
        title.title = "Title from a"
        try left.perform(.updateTask(title))
        var priority = task
        priority.priority = 2
        try right.perform(.updateTask(priority))
        let result = try converged(left, right)
        precondition(result.state.tasks[task.id]?.title == title.title)
        precondition(result.state.tasks[task.id]?.priority == 2)
        var competing = priority
        competing.title = "Title from b"
        try right.perform(.updateTask(competing))
        let winner = try converged(left, right)
        precondition(winner.state.tasks[task.id]?.title == competing.title)
        var observed = try TodoReplication.merge(local: left, remote: right.envelopes, now: now)
        guard var latest = observed.state.tasks[task.id] else { preconditionFailure("task missing") }
        latest.title = "Causally later"
        try observed.perform(.updateTask(latest))
        let causal = try converged(observed, right)
        precondition(causal.state.tasks[task.id]?.title == latest.title)
        print("PASS: concurrent edits converge in both orders, causal clock and idempotent re-delivery")
    }

    static func fields() throws {
        let mutations: [(inout TodoTask) -> Void] = [
            { $0.title = "Changed" }, { $0.description = "Markdown" },
            { $0.due = .init(date: now, isAllDay: true, normalized: "today") },
            { $0.priority = 1 }, { $0.labels = [label.id] },
            { $0.sectionID = progress.id }, { $0.completedAt = now }
        ]
        let alternatives: [(inout TodoTask) -> Void] = [
            { $0.title = "Other title" }, { $0.description = "Other description" },
            { $0.due = .init(date: now.addingTimeInterval(60), isAllDay: true, normalized: "later") },
            { $0.priority = 2 }, { $0.labels = [otherLabel.id] },
            { $0.sectionID = blocked.id }, { $0.completedAt = now.addingTimeInterval(60) }
        ]
        for index in mutations.indices {
            var left = try replica("a")
            var right = try replica("b")
            var first = task
            var second = task
            mutations[index](&first)
            alternatives[index](&second)
            try left.perform(.updateTask(first))
            try right.perform(.updateTask(second))
            let result = try converged(left, right)
            precondition(result.state.tasks[task.id] == second, "same-field LWW \(index)")
        }
        for firstIndex in mutations.indices {
            for secondIndex in mutations.indices where firstIndex != secondIndex {
                var left = try replica("a")
                var right = try replica("b")
                var first = task
                var second = task
                mutations[firstIndex](&first)
                mutations[secondIndex](&second)
                try left.perform(.updateTask(first))
                try right.perform(.updateTask(second))
                var expected = task
                mutations[firstIndex](&expected)
                mutations[secondIndex](&expected)
                let result = try converged(left, right)
                precondition(result.state.tasks[task.id] == expected, "field pair \(firstIndex), \(secondIndex)")
            }
        }
        var left = try replica("a")
        var right = try replica("b")
        var first = task
        var second = task
        first.title = "a"
        second.title = "b"
        try left.perform(.updateTask(first))
        try right.perform(.updateTask(second))
        let result = try converged(left, right)
        precondition(result.state.tasks[task.id]?.title == "b")
        try left.perform(.addComment(taskID: task.id, comment: .init(id: UUID().uuidString, text: "a", createdAt: now)))
        try right.perform(.addComment(taskID: task.id, comment: .init(id: UUID().uuidString, text: "b", createdAt: now)))
        let comments = try converged(left, right)
        precondition(Set(comments.state.tasks[task.id]?.comments.map(\.text) ?? []) == ["a", "b"])
        print("PASS: all seven field groups preserve independent edits; equal-time replica tie-break and concurrent comments")
    }

    static func deletion() throws {
        var left = try replica("a")
        var right = try replica("b")
        try left.perform(.deleteTask(id: task.id))
        var edit = task
        edit.title = "Late edit"
        try right.perform(.updateTask(edit))
        edit.description = "Even later"
        try right.perform(.updateTask(edit))
        let result = try converged(left, right)
        precondition(result.state.tasks[task.id] == nil)
        let inverse = try right.perform(.deleteTask(id: task.id))
        try right.perform(inverse)
        let restored = try converged(left, right)
        precondition(restored.state.tasks[task.id] == nil)
        var childReplica = try replica("c")
        let child = TodoTask(id: UUID().uuidString, title: "Child", projectID: project.id,
                             sectionID: backlog.id, parentID: task.id)
        try childReplica.perform(.addTask(child))
        var projectDelete = try replica("d")
        try projectDelete.perform(.deleteProject(id: project.id))
        let cascade = try converged(childReplica, projectDelete)
        precondition(cascade.state.tasks.count == 1 && cascade.state.sections.isEmpty)
        precondition(cascade.state.tasks[child.id]?.projectID == nil)
        precondition(cascade.orphansRecovered.map(\.taskID) == [child.id])
        var sectionDelete = try replica("e")
        try sectionDelete.perform(.deleteSection(id: progress.id))
        var move = try replica("f")
        try move.perform(.moveTask(id: task.id, projectID: project.id, sectionID: progress.id, parentID: nil))
        let moved = try converged(sectionDelete, move)
        precondition(moved.state.tasks[task.id]?.sectionID == nil)
        print("PASS: delete wins over earlier/later edits; explicit undo restores; project and section conflicts stay valid")
    }

    static func replay() throws {
        var value = try fixture()
        let filter = TodoSavedFilter(id: UUID().uuidString, name: "Urgent", query: "p1")
        let comment = TodoComment(id: UUID().uuidString, text: "first", createdAt: now)
        let earlier = TodoComment(id: UUID().uuidString, text: "backdated", createdAt: now.addingTimeInterval(-60))
        let commands: [TodoCommand] = [
            .addFilter(filter), .renameFilter(id: filter.id, name: "Focus"),
            .updateFilter(.init(id: filter.id, name: "Focus", query: "today")),
            .renameProject(id: project.id, name: "Renamed"), .renameSection(id: backlog.id, name: "Next"),
            .renameLabel(id: label.id, name: "renamed"), .addComment(taskID: task.id, comment: comment),
            .addComment(taskID: task.id, comment: earlier), .reorder(kind: .task, orders: [task.id: 8]),
            .deleteLabel(id: label.id), .deleteFilter(id: filter.id), .deleteProject(id: project.id)
        ]
        for command in commands {
            let before = value.state
            let inverse = try value.perform(command)
            let merged = try TodoReplication.merge(local: TodoReplication(replicaID: "reader"),
                                                   remote: value.envelopes, now: now)
            precondition(merged.state == value.state, "single-replica replay changed \(command)")
            try value.perform(inverse)
            let undone = try TodoReplication.merge(local: TodoReplication(replicaID: "reader"),
                                                   remote: value.envelopes, now: now)
            precondition(undone.state == before && value.state == before)
            try value.perform(command)
        }
        print("PASS: command batches, cascades, inverses and backdated comments retain single-replica replay semantics")
    }

    static func relationships() throws {
        let child = TodoTask(id: UUID().uuidString, title: "Child", projectID: project.id, sectionID: backlog.id)
        let descendant = TodoTask(id: UUID().uuidString, title: "Descendant", projectID: project.id,
                                  sectionID: backlog.id, parentID: task.id)
        var base = try fixture()
        try base.perform(.addTask(child))
        try base.perform(.addTask(descendant))
        var left = try TodoReplication.merge(local: TodoReplication(replicaID: "a"), remote: base.envelopes, now: now)
        var right = try TodoReplication.merge(local: TodoReplication(replicaID: "b"), remote: base.envelopes, now: now)
        try left.perform(.moveTask(id: task.id, projectID: project.id, sectionID: backlog.id, parentID: child.id))
        try right.perform(.moveTask(id: child.id, projectID: project.id, sectionID: backlog.id, parentID: task.id))
        let cycle = try converged(left, right)
        precondition(cycle.state.tasks.values.filter { $0.parentID == nil }.count == 1)
        precondition(cycle.state.tasks[descendant.id]?.parentID == task.id)
        var deleted = try replica("delete")
        try deleted.perform(.deleteTask(id: task.id))
        var added = try replica("new")
        var newChild = child
        newChild.parentID = task.id
        try added.perform(.addTask(newChild))
        let orphan = try converged(deleted, added)
        precondition(orphan.state.tasks[child.id]?.parentID == nil && orphan.state.tasks[child.id]?.projectID == nil)
        precondition(orphan.orphansRecovered.map(\.taskID) == [child.id])
        print("PASS: concurrent parent cycles and descendants of deleted parents preserve store invariants")
    }

    static func vectors() throws {
        var source = try replica("a")
        try source.perform(.completeTask(id: task.id, at: now))
        try source.perform(.uncompleteTask(id: task.id))
        let own = source.envelopes.filter { $0.replicaID == "a" }
        var destination = try TodoReplication.merge(local: TodoReplication(replicaID: "b"), remote: [own[1]], now: now)
        precondition(destination.vectorClock.sequences["a"] == 0)
        let missing = source.envelopes(after: destination.vectorClock)
        precondition(missing.contains(own[0]))
        destination = try TodoReplication.merge(local: destination, remote: missing, now: now)
        precondition(destination.state == source.state)
        precondition(source.envelopes(after: destination.vectorClock).isEmpty)
        var conflict = own[0]
        conflict = TodoEnvelope(replicaID: conflict.replicaID, sequence: conflict.sequence,
                                timestamp: conflict.timestamp + 1, command: conflict.command, changes: conflict.changes)
        do {
            _ = try TodoReplication.merge(local: destination, remote: [conflict], now: now)
            preconditionFailure("accepted conflicting envelope")
        } catch TodoReplicationError.conflictingEnvelope { }
        print("PASS: vector exchange retains holes and refuses conflicting operation identities")
    }

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0) ?? value.timeZone
        return value
    }

    @discardableResult
    static func request(_ request: TodoAgentRequest, on replica: inout TodoReplication,
                        at date: Date = now) throws -> TodoAgentResponse {
        let plan = try TodoAgentAPI.plan(request, state: replica.state, now: date, calendar: calendar,
                                        staleAfterMinutes: 10, makeID: { UUID().uuidString })
        try replica.perform(plan.command)
        return plan.response
    }

    static func agents() throws {
        var value = try replica("agent")
        let listed = try request(.list(query: "p1", sectionID: backlog.id), on: &value)
        precondition(listed == .tasks([task]))
        let lowPriority = try request(.list(query: "p4", sectionID: nil), on: &value)
        precondition(lowPriority == .tasks([]))
        try request(.claim(taskID: task.id, agent: "builder"), on: &value)
        precondition(value.state.tasks[task.id]?.sectionID == progress.id)
        precondition(value.state.tasks[task.id]?.claim?.agent == "builder")
        precondition(value.state.tasks[task.id]?.comments.last?.text == "claimed by builder")
        let claimed = value.state
        try request(.claim(taskID: task.id, agent: "builder"), on: &value)
        precondition(value.state == claimed)
        do {
            try request(.claim(taskID: task.id, agent: "other"), on: &value)
            preconditionFailure("stole claim")
        } catch TodoAgentError.claimedBy("builder") { }
        try request(.comment(taskID: task.id, agent: "builder", text: "working"), on: &value,
                    at: now.addingTimeInterval(9 * 60))
        try request(.releaseExpired, on: &value, at: now.addingTimeInterval(10 * 60))
        precondition(value.state.tasks[task.id]?.claim != nil)
        try request(.move(taskID: task.id, agent: "builder", sectionID: blocked.id), on: &value,
                    at: now.addingTimeInterval(11 * 60))
        precondition(value.state.tasks[task.id]?.sectionID == blocked.id)
        try request(.releaseExpired, on: &value, at: now.addingTimeInterval(21 * 60))
        precondition(value.state.tasks[task.id]?.claim == nil && value.state.tasks[task.id]?.sectionID == blocked.id)
        try request(.claim(taskID: task.id, agent: "builder"), on: &value, at: now.addingTimeInterval(22 * 60))
        try request(.release(taskID: task.id, agent: "builder"), on: &value, at: now.addingTimeInterval(23 * 60))
        precondition(value.state.tasks[task.id]?.claim == nil)
        try request(.release(taskID: task.id, agent: "builder"), on: &value, at: now.addingTimeInterval(23 * 60))
        try request(.complete(taskID: task.id, agent: "builder"), on: &value, at: now.addingTimeInterval(24 * 60))
        precondition(value.state.tasks[task.id]?.completedAt == now.addingTimeInterval(24 * 60))
        let completed = try request(.list(query: nil, sectionID: nil), on: &value)
        precondition(completed == .tasks([]))
        let unchanged = value.state
        do {
            try request(.list(query: "nonsense", sectionID: nil), on: &value)
            preconditionFailure("invalid filter accepted")
        } catch TodoAgentError.invalidFilter { }
        precondition(value.state == unchanged)
        let merged = try converged(value, replica("observer"))
        precondition(merged.state.tasks[task.id]?.claim == nil)
        print("PASS: agent filter priorities, claim ownership, dated comments, move, complete, release and fake-clock expiry")
    }

    static func agentFailures() throws {
        var value = try replica("a")
        try value.perform(.deleteSection(id: progress.id))
        do {
            try request(.claim(taskID: task.id, agent: "builder"), on: &value)
            preconditionFailure("claim invented a workflow section")
        } catch TodoAgentError.inProgressSectionRequired { }
        do {
            try request(.claim(taskID: task.id, agent: "  "), on: &value)
            preconditionFailure("empty agent accepted")
        } catch TodoAgentError.invalidAgent { }
        let missing = UUID().uuidString
        do {
            try request(.comment(taskID: missing, agent: "builder", text: "hello"), on: &value)
            preconditionFailure("missing task accepted")
        } catch TodoAgentError.unknownTask(let id) { precondition(id == missing) }
        try value.perform(.addSection(progress))
        try request(.claim(taskID: task.id, agent: "builder"), on: &value)
        let before = value.state
        do {
            try request(.move(taskID: task.id, agent: "other", sectionID: backlog.id), on: &value)
            preconditionFailure("other agent moved claimed task")
        } catch TodoAgentError.claimedBy { }
        precondition(value.state == before)
        try request(.release(taskID: task.id, agent: "builder"), on: &value, at: now.addingTimeInterval(600))
        precondition(value.state.tasks[task.id]?.claim == nil)
        do {
            _ = try TodoAgentAPI.plan(.releaseExpired, state: value.state, now: now, calendar: calendar,
                                      staleAfterMinutes: 0, makeID: { UUID().uuidString })
            preconditionFailure("zero timeout accepted")
        } catch TodoAgentError.invalidTimeout { }
        print("PASS: typed agent failures, no implicit sections, atomic rejection and idempotent release after expiry")
    }

    static func reviewRegressions() throws {
        let child = TodoTask(id: UUID().uuidString, title: "Independent deletion", projectID: project.id,
                             sectionID: backlog.id, parentID: task.id)
        var base = try fixture()
        try base.perform(.addTask(child))
        for (first, second) in [("a", "b"), ("b", "a")] {
            var left = try TodoReplication.merge(local: TodoReplication(replicaID: first), remote: base.envelopes, now: now)
            var right = try TodoReplication.merge(local: TodoReplication(replicaID: second), remote: base.envelopes, now: now)
            let inverse = try left.perform(.deleteProject(id: project.id))
            try right.perform(.deleteTask(id: child.id))
            try left.perform(inverse)
            let merged = try converged(left, right)
            precondition(merged.state.projects[project.id] != nil && merged.state.tasks[task.id] != nil)
            precondition(merged.state.tasks[child.id] == nil, "undo restored another replica's deletion")
        }
        var claimed = try TodoReplication.merge(local: TodoReplication(replicaID: "agent"), remote: base.envelopes, now: now)
        try request(.claim(taskID: child.id, agent: "builder"), on: &claimed)
        precondition(claimed.state.tasks[child.id]?.parentID == task.id)
        precondition(claimed.state.tasks[child.id]?.sectionID == backlog.id)
        try request(.release(taskID: child.id, agent: "builder"), on: &claimed)
        precondition(claimed.state.tasks[child.id]?.parentID == task.id)
        try request(.claim(taskID: task.id, agent: "builder"), on: &claimed)
        try request(.release(taskID: task.id, agent: "builder"), on: &claimed)
        precondition(claimed.state.tasks[task.id]?.sectionID == backlog.id)
        var recurring = task
        recurring.due = .init(date: now, isAllDay: true, recurrenceRule: "every day", normalized: "daily")
        try claimed.perform(.updateTask(recurring))
        try claimed.perform(.completeTask(id: child.id, at: now))
        try request(.complete(taskID: task.id, agent: "builder"), on: &claimed)
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        precondition(claimed.state.tasks[task.id]?.due?.date == next)
        precondition(claimed.state.tasks[task.id]?.completedAt == nil)
        precondition(claimed.state.tasks[child.id]?.completedAt == nil)
        recurring.due?.recurrenceRule = "unparseable recurrence"
        try claimed.perform(.updateTask(recurring))
        let before = claimed.state
        do {
            try request(.complete(taskID: task.id, agent: "builder"), on: &claimed)
            preconditionFailure("unsupported recurrence ended series")
        } catch TodoAgentError.unsupportedRecurrence { }
        precondition(claimed.state == before)
        print("PASS: undo preserves independent deletes; child claims keep parents; release respects moves; recurrence advances")
    }

    static func clockQuarantine() throws {
        let base = try fixture()
        guard let original = base.envelopes.first else { preconditionFailure("no fixture envelope") }
        let bad = TodoEnvelope(replicaID: "bad-clock", sequence: 1, timestamp: UInt64.max,
                               command: original.command, changes: original.changes)
        var merged = try TodoReplication.merge(local: base, remote: [bad], now: now)
        precondition(merged.deferredEnvelopes == [bad] && merged.clockErrors.count == 1)
        guard case .timestampAhead(let id, _, _) = merged.clockErrors[0] else {
            preconditionFailure("untyped clock error")
        }
        precondition(id == bad.id && merged.vectorClock.sequences[bad.replicaID] == nil)
        try merged.perform(.completeTask(id: task.id, at: now))
        precondition(merged.state.tasks[task.id]?.completedAt == now)
        let timestamp = UInt64((now.timeIntervalSince1970 + 86_460) * 1_000)
        let future = TodoEnvelope(replicaID: "future", sequence: 1, timestamp: timestamp,
                                  command: original.command, changes: original.changes)
        let pending = try TodoReplication.merge(local: TodoReplication(replicaID: "local"), remote: [future], now: now)
        precondition(pending.state.tasks.isEmpty && pending.deferredEnvelopes == [future])
        let accepted = try TodoReplication.merge(local: pending, remote: [], now: now.addingTimeInterval(61))
        precondition(accepted.state == base.state && accepted.deferredEnvelopes.isEmpty && accepted.clockErrors.isEmpty)
        print("PASS: future timestamps produce typed quarantine errors, remain retryable and cannot exhaust the local clock")
    }

    static func performance(_ directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct ReceiveRecord: Encodable {
            let schemaVersion = 1
            let command = TodoCommand.batch([])
            let isUndo = false
            let received: [TodoEnvelope]
        }
        var envelopes: [TodoEnvelope] = []
        for index in 1...10_100 {
            let task = TodoTask(id: UUID().uuidString, title: "Performance \(index)")
            let command = TodoCommand.addTask(task)
            var after = TodoState()
            try after.apply(command)
            envelopes.append(TodoEnvelope(replicaID: "performance", sequence: UInt64(index), timestamp: UInt64(index),
                                          command: command,
                                          changes: TodoReplicationChanges(command: command, before: TodoState(), after: after)))
        }
        var data = Data()
        let encoder = JSONEncoder()
        for offset in stride(from: 0, to: 10_000, by: 20) {
            data.append(try encoder.encode(ReceiveRecord(received: Array(envelopes[offset..<(offset + 20)]))))
            data.append(0x0A)
        }
        try data.write(to: directory.appending(path: "commands.jsonl"))
        let start = ContinuousClock.now
        let store = try await TodoStore.open(directory: directory, now: now)
        let opened = start.duration(to: .now)
        precondition(store.state.tasks.count == 10_000)
        let receiving = ContinuousClock.now
        try store.receive(Array(envelopes.suffix(100)), now: now)
        let received = receiving.duration(to: .now)
        precondition(store.state.tasks.count == 10_100)
        let tail = TodoTask(id: UUID().uuidString, title: "Local tail after receive")
        try store.perform(.addTask(tail))
        let expected = store.state
        try store.close()
        let restored = try await TodoStore.open(directory: directory, now: now)
        precondition(restored.state == expected)
        precondition(restored.canUndo)
        try restored.undo()
        precondition(restored.state.tasks.count == 10_100 && restored.state.tasks[tail.id] == nil)
        try restored.close()
        print("PASS: 10k/500-record open \(opened); 100-envelope receive onto 10k \(received)")
    }

    static func quarantinePersistence(_ directory: URL) async throws {
        let store = try await TodoStore.open(directory: directory, now: now)
        let original = try fixture().envelopes[0]
        let future = TodoEnvelope(replicaID: "future", sequence: 1,
                                  timestamp: UInt64((now.timeIntervalSince1970 + 86_460) * 1_000),
                                  command: original.command, changes: original.changes)
        let errors = try store.receive([future], now: now)
        precondition(errors.count == 1 && store.state.tasks.isEmpty)
        try store.close()
        let pending = try await TodoStore.open(directory: directory, now: now)
        precondition(pending.replication.deferredEnvelopes == [future])
        try pending.receive([], now: now.addingTimeInterval(61))
        precondition(pending.state.tasks[task.id] == task && pending.replication.clockErrors.isEmpty)
        try pending.close()
        let restored = try await TodoStore.open(directory: directory, now: now.addingTimeInterval(61))
        precondition(restored.state.tasks[task.id] == task && restored.replication.deferredEnvelopes.isEmpty)
        try restored.close()
        print("PASS: quarantined envelopes survive reopen and become usable when the injected clock catches up")
    }

    static func json() throws {
        let requests: [TodoAgentRequest] = [.list(query: "p1", sectionID: nil), .claim(taskID: task.id, agent: "builder"),
            .comment(taskID: task.id, agent: "builder", text: "hello"),
            .move(taskID: task.id, agent: "builder", sectionID: progress.id),
            .complete(taskID: task.id, agent: "builder"), .release(taskID: task.id, agent: "builder"), .releaseExpired]
        for request in requests {
            let decoded = try JSONDecoder().decode(TodoAgentRequest.self, from: JSONEncoder().encode(request))
            precondition(decoded == request)
        }
        let responses: [TodoAgentResponse] = [.tasks([task]), .task(task), .released([task.id])]
        for response in responses {
            let decoded = try JSONDecoder().decode(TodoAgentResponse.self, from: JSONEncoder().encode(response))
            precondition(decoded == response)
        }
        let envelopes = try fixture().envelopes
        let decoded = try JSONDecoder().decode([TodoEnvelope].self, from: JSONEncoder().encode(envelopes))
        precondition(decoded == envelopes)
        let error = TodoAgentError.claimedBy("builder")
        let decodedError = try JSONDecoder().decode(TodoAgentError.self, from: JSONEncoder().encode(error))
        precondition(decodedError == error)
    }

    static func persistence(_ root: URL) async throws {
        let directory = root.appending(path: "old")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct LegacyRecord: Encodable { let schemaVersion = 1; let command: TodoCommand; let isUndo: Bool }
        var data = Data()
        let commands: [TodoCommand] = [.addProject(project), .addSection(backlog), .addSection(progress), .addTask(task)]
        for command in commands {
            data.append(try JSONEncoder().encode(LegacyRecord(command: command, isUndo: false)))
            data.append(0x0A)
        }
        let url = directory.appending(path: "commands.jsonl")
        try data.write(to: url)
        let first = try await TodoStore.open(directory: directory)
        precondition(first.state.tasks[task.id] == task)
        precondition(first.replication.envelopes.map(\.timestamp) == [1, 2, 3, 4])
        let identity = first.replication.replicaID
        try first.close()
        let reopened = try await TodoStore.open(directory: directory)
        precondition(reopened.replication.replicaID == identity)
        let second = try await TodoStore.open(directory: root.appending(path: "new"))
        try second.receive(reopened.replication.envelopes)
        precondition(!second.canUndo)
        _ = try reopened.request(.claim(taskID: task.id, agent: "builder"), now: now, calendar: calendar,
                                 staleAfterMinutes: 10, makeID: { UUID().uuidString })
        _ = try second.request(.comment(taskID: task.id, agent: "observer", text: "concurrent"), now: now,
                               calendar: calendar, staleAfterMinutes: 10, makeID: { UUID().uuidString })
        precondition(second.canUndo)
        try second.receive(second.replication.envelopes)
        precondition(second.canUndo)
        try reopened.receive(second.replication.envelopes(after: reopened.replication.vectorClock))
        try second.receive(reopened.replication.envelopes(after: second.replication.vectorClock))
        precondition(reopened.state == second.state)
        let intact = try Data(contentsOf: url)
        guard let original = reopened.replication.envelopes.first else { preconditionFailure("no envelopes") }
        let invalid = TodoEnvelope(replicaID: original.replicaID, sequence: original.sequence,
                                   timestamp: original.timestamp + 1, command: original.command, changes: original.changes)
        do {
            try reopened.receive([invalid])
            preconditionFailure("conflicting receive persisted")
        } catch TodoReplicationError.conflictingEnvelope { }
        let unchanged = try Data(contentsOf: url)
        precondition(unchanged == intact)
        let expected = reopened.state
        let clock = reopened.replication.vectorClock
        try reopened.close()
        try second.close()
        let restored = try await TodoStore.open(directory: directory)
        let peer = try await TodoStore.open(directory: root.appending(path: "new"))
        precondition(restored.state == expected && peer.state == expected)
        precondition(restored.replication.vectorClock == clock)
        try restored.receive(peer.replication.envelopes)
        precondition(restored.state == expected)
        try restored.close()
        try peer.close()
        print("PASS: legacy commands receive stable replica/order clocks; durable sync, claims, restart and duplicate delivery")
    }
}
