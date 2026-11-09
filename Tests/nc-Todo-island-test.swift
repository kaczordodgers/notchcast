// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoIsland*.swift
// notchcast-sources: Tinycast/Features/Todo/TodoModule.swift
import Foundation
import Observation

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor @Observable final class IslandSwitch {
    var enabled = false
}

@main @MainActor
struct TodoIslandTests {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        var now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 23, minute: 58))!
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await TodoStore.open(directory: root.appending(path: "store"))
        defer { try? store.close() }
        let url = root.appending(path: "snapshot.json")
        let feed = TodoIslandFeed(store: store, fileURL: url, calendar: calendar, now: { now })
        feed.start()
        defer { feed.stop() }
        let due = now.addingTimeInterval(60)
        let task = TodoTask(id: UUID().uuidString, title: "Timed", priority: 4,
                            due: .init(date: due, time: DateComponents(hour: 23, minute: 59),
                                       isAllDay: false, normalized: ""))
        try store.perform(.addTask(task))
        for _ in 0..<5 { await Task.yield() }
        precondition(feed.snapshot.today.map(\.id) == [task.id])
        precondition(feed.snapshot.attention == .none)
        precondition(feed.nextBoundary == due)
        now = due
        feed.refresh()
        precondition(feed.snapshot.attention == .dueNow)
        now = calendar.date(byAdding: .minute, value: 1, to: now)!
        feed.refresh()
        precondition(feed.snapshot.attention == .overdue)
        try store.perform(TodoCompletion.command(id: task.id, state: store.state, now: now, calendar: calendar))
        feed.refresh()
        precondition(store.state.tasks[task.id]?.completedAt == now)
        precondition(feed.snapshot.attention == .none)
        var recurring = task
        recurring = TodoTask(id: UUID().uuidString, title: "Repeat", due: .init(
            date: now, isAllDay: true, recurrenceRule: "every day", normalized: ""))
        try store.perform(.addTask(recurring))
        try store.perform(TodoCompletion.command(id: recurring.id, state: store.state, now: now, calendar: calendar))
        feed.refresh()
        precondition(store.state.tasks[recurring.id]?.completedAt == nil)
        precondition(calendar.component(.day, from: store.state.tasks[recurring.id]!.due!.date) == 30)
        precondition(feed.snapshot.tomorrow.map(\.id) == [recurring.id])
        for index in 0..<20 {
            let date = calendar.date(byAdding: .day, value: index == 0 ? -1 : 0, to: now)!
            try store.perform(.addTask(TodoTask(id: UUID().uuidString, title: "Task \(index)",
                priority: index == 1 ? 4 : 1,
                due: .init(date: date, isAllDay: true, normalized: ""))))
        }
        feed.refresh()
        precondition(feed.snapshot.overdue.count == 1)
        precondition(feed.snapshot.today.count == 15)
        precondition(feed.snapshot.today.first?.priority == 4)
        precondition(feed.snapshot.tomorrow.isEmpty)
        precondition(feed.snapshot.overflowCount == 5)
        let decoded = try JSONDecoder().decode(TodoIslandSnapshot.self, from: Data(contentsOf: url))
        precondition(decoded == feed.snapshot)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        precondition(files == ["snapshot.json", "store"])
        print("PASS: ordering, overflow, attention boundaries, DST recurrence, completion, atomic decode")
        let toggle = IslandSwitch()
        let module = TodoModule(directory: root.appending(path: "module"),
                                islandEnabled: { toggle.enabled }, showFailure: { _ in preconditionFailure() })
        module.start()
        for _ in 0..<500 where module.store == nil { try await Task.sleep(for: .milliseconds(10)) }
        precondition(module.store != nil && module.islandSnapshot == nil)
        toggle.enabled = true
        for _ in 0..<20 { await Task.yield() }
        weak var released = module.islandFeed
        precondition(released != nil && module.islandSnapshot != nil)
        let islandFile = root.appending(path: "module/island.json").path
        for _ in 0..<500 where !FileManager.default.fileExists(atPath: islandFile) { try await Task.sleep(for: .milliseconds(10)) }
        precondition(FileManager.default.fileExists(atPath: islandFile))
        toggle.enabled = false
        for _ in 0..<20 { await Task.yield() }
        precondition(released == nil && module.islandSnapshot == nil)
        precondition(!FileManager.default.fileExists(atPath: islandFile), "switching off deletes the snapshot file")
        module.stop()
        toggle.enabled = true
        module.start()
        precondition(module.islandFeed == nil)
        for _ in 0..<500 where module.store == nil { try await Task.sleep(for: .milliseconds(10)) }
        released = module.islandFeed
        precondition(released != nil)
        try module.store?.close()
        for _ in 0..<20 { await Task.yield() }
        precondition(released == nil && module.islandSnapshot == nil)
        module.stop()
        module.start()
        for _ in 0..<500 where module.store == nil { try await Task.sleep(for: .milliseconds(10)) }
        released = module.islandFeed
        precondition(released != nil)
        module.stop()
        precondition(released == nil && module.islandSnapshot == nil)
        print("PASS: module switch, delayed store open, close and stop release the feed")
    }
}
