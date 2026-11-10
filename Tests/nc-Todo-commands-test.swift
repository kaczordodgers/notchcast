// notchcast-sources: Tinycast/Features/Todo/Model/*.swift Tinycast/Features/Todo/Service/TodoStore*.swift
// notchcast-sources: Tinycast/Features/Todo/Commands/*.swift Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import Foundation
import Observation

enum SystemLanguages {
    static let preferred = ["pl-PL"]
}

@MainActor @Observable
final class RefreshState {
    var value = 0
}

enum SettingsTab: Sendable { case notchcast }
struct AppEntry {
    enum Kind { case command }
    init(id: String, name: String, url: URL, bundleID: String?, kind: Kind,
         settingsOwner: SettingsTab?, symbolName: String) {}
}
@MainActor final class AppCore {
    static let shared = AppCore()
    func showMessage(_ message: String) { preconditionFailure("Production feedback used") }
}
@MainActor final class TodoModule {
    static var shared: TodoModule?
    var store: TodoStore?
}

@main @MainActor
struct TodoCommandTests {
    static var enabled = true
    static var clipboard: String?
    static var reads = 0
    static var messages: [String] = []
    static var store: TodoStore?

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let opened = try await TodoStore.open(directory: directory)
        store = opened
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let context = TodoCommandContext(isEnabled: { enabled }, store: { store },
            clipboardText: { reads += 1; return clipboard }, report: { messages.append($0) },
            now: { now }, calendar: calendar, language: .english)
        let defaultContext = TodoCommandContext(isEnabled: { enabled }, store: { store },
            clipboardText: { clipboard }, report: { messages.append($0) })
        precondition(defaultContext.language == .polish)
        let commands = TodoCommands.commands(context: { context })
        precondition(commands.map(\.slug) == ["add-task-from-clipboard", "complete-next-task", "undo-last-task-change"])
        for command in commands {
            enabled = false
            let before = opened.state
            let count = messages.count
            precondition(!command.isEnabled())
            command.run()
            precondition(opened.state == before && reads == 0 && messages.count == count + 1)
        }
        enabled = true
        precondition(commands.allSatisfy { $0.isEnabled() })
        for text in [nil, "", " \n "] as [String?] {
            clipboard = text
            commands[0].run()
            precondition(opened.state.tasks.isEmpty && !opened.canUndo)
        }
        commands[1].run()
        precondition(messages.last == "There are no tasks due today.")
        commands[2].run()
        precondition(messages.last == "There is no task change to undo.")
        let label = TodoLabel(id: UUID().uuidString, name: "work")
        try opened.perform(.addLabel(label))
        clipboard = "Ship tomorrow p1 @work"
        commands[0].run()
        guard let added = opened.state.tasks.values.first else { preconditionFailure("No task added") }
        precondition(added.title == "Ship" && added.priority == 4 && added.labels == [label.id])
        precondition(added.due.map { calendar.isDate($0.date, inSameDayAs: now.addingTimeInterval(86400)) } == true)
        let overdue = TodoTask(id: UUID().uuidString, title: "Overdue", due:
            .init(date: now.addingTimeInterval(-86400), isAllDay: true, normalized: "yesterday"))
        let today = TodoTask(id: UUID().uuidString, title: "Today", due:
            .init(date: now, isAllDay: true, normalized: "today"))
        try opened.perform(.batch([.addTask(today), .addTask(overdue)]))
        let before = opened.state
        commands[1].run()
        precondition(opened.state.tasks[overdue.id]?.completedAt == now)
        precondition(opened.state.tasks[today.id]?.completedAt == nil)
        commands[2].run()
        precondition(opened.state == before)
        let repeating = TodoTask(id: UUID().uuidString, title: "Repeat", due: .init(date: now.addingTimeInterval(-2 * 86400),
            isAllDay: true, recurrenceRule: "every 1 days", normalized: "every 1 days"))
        try opened.perform(.addTask(repeating))
        commands[1].run()
        let repeated = opened.state.tasks[repeating.id]
        precondition(repeated?.completedAt == nil, "Complete Next Task closed a repeating task for good")
        let nextDay = calendar.startOfDay(for: now.addingTimeInterval(86400))
        precondition(repeated?.due?.date == nextDay, "Repeating task due \(String(describing: repeated?.due?.date))")
        precondition(opened.state.tasks[overdue.id]?.completedAt == nil)
        commands[2].run()
        commands[2].run()
        precondition(opened.state == before)
        enabled = false
        let readCount = reads
        for command in commands { command.run() }
        precondition(opened.state == before && reads == readCount)
        enabled = true
        store = nil
        for command in commands {
            command.run()
            precondition(messages.last == "The task store is unavailable.")
        }
        let suite = "todo-commands.\(UUID().uuidString)"
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        var refreshes = 0
        let refreshState = RefreshState()
        let observer = TodoCommandAvailability(preferences: preferences) {
            _ = refreshState.value
            refreshes += 1
        }
        precondition(refreshes == 1)
        refreshState.value += 1
        for _ in 0..<50 { await Task.yield() }
        precondition(refreshes == 1)
        preferences.set(.tasks, true)
        for _ in 0..<50 where refreshes < 2 { await Task.yield() }
        precondition(refreshes >= 2)
        preferences.set(.tasks, false)
        for _ in 0..<50 where refreshes < 3 { await Task.yield() }
        precondition(refreshes >= 3)
        withExtendedLifetime(observer) {}
        try opened.close()
        print("PASS: all three commands on/off, fake clipboard, parsed metadata, Today order, undo and availability")
    }
}
