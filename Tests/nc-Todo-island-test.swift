// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoIsland*.swift
import Foundation

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
        try feed.complete(task.id)
        precondition(store.state.tasks[task.id]?.completedAt == now)
        precondition(feed.snapshot.attention == .none)
        var recurring = task
        recurring = TodoTask(id: UUID().uuidString, title: "Repeat", due: .init(
            date: now, isAllDay: true, recurrenceRule: "every day", normalized: ""))
        try store.perform(.addTask(recurring))
        try feed.complete(recurring.id)
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
    }
}
