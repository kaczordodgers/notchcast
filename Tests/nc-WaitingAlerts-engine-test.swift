// notchcast-sources: -strict-concurrency=complete -lsqlite3
// notchcast-sources: Tinycast/Features/WaitingAlerts/Model/*.swift Tinycast/Features/WaitingAlerts/Service/*.swift
// notchcast-sources: Tinycast/Features/FileSearch/Service/FileSystemWatcher.swift
// notchcast-sources: Tinycast/Features/WaitingAlerts/WaitingAlertsModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
import Foundation
import SQLite3

typealias NotchcastFeature = TestFeature
enum TestFeature { case waitingAlerts, agentThreads }
enum DialogTone { case neutral }
struct NotchcastCommand {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: TestFeature
    let isEnabled: @MainActor () -> Bool
    let run: @MainActor () -> Void
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = false
    func isOn(_ feature: TestFeature) -> Bool { enabled }
}
@MainActor final class AppCore {}
@MainActor final class FakeWatcher: WaitingAlertsWatching {
    var changed: (@MainActor () -> Void)?
    var exists = true
    var stops = 0
    func start(path: String, changed: @escaping @MainActor () -> Void) -> Bool {
        self.changed = changed
        return exists
    }
    func stop() { stops += 1; changed = nil }
}
@MainActor final class Fixture: WaitingAlertsReading {
    var calls = 0
    var rows: [WaitingAlert] = []
    var messages: [String] = []
    var readGate: CheckedContinuation<Void, Never>?
    var block = false
    var fail = false
    func read() async throws -> [WaitingAlert] {
        calls += 1
        if block { await withCheckedContinuation { readGate = $0 } }
        if fail { throw WaitingAlertsFailure.unavailable }
        return rows
    }
}
@main struct WaitingAlertsTest {
    static func wait(_ id: String, _ kind: WaitingAlert.Kind) -> WaitingAlert {
        WaitingAlert(id: id, title: "Example", kind: kind)
    }
    @MainActor static func settle() async { for _ in 0..<30 { await Task.yield() } }
    @MainActor static func main() async throws {
        try await verifyReader()
        try await verifyWatcher()
        let approval = [wait("one", .approval)]
        let question = [wait("two", .question)]
        precondition(WaitingAlertsEngine.notices(previous: nil, current: approval).isEmpty)
        precondition(WaitingAlertsEngine.notices(previous: [], current: approval) == approval)
        precondition(WaitingAlertsEngine.notices(previous: approval, current: approval).isEmpty)
        precondition(WaitingAlertsEngine.notices(previous: approval, current: []).isEmpty)
        precondition(WaitingAlertsEngine.notices(previous: [], current: approval) == approval)
        precondition(WaitingAlertsEngine.message(approval, total: 3) == "Example is waiting for approval.")
        precondition(WaitingAlertsEngine.message(question, total: 1) == "Example has a question.")
        precondition(WaitingAlertsEngine.message(approval + question, total: 2) == "2 agents are waiting.")
        precondition(WaitingAlertsEngine.message(approval + question, total: 5) == "5 agents are waiting.")
        precondition(WaitingAlertsEngine.message([], total: 5) == nil)
        precondition(WaitingAlertsEngine.countMessage(0) == "No agents are waiting.")
        let fixture = Fixture()
        let watcher = FakeWatcher()
        fixture.rows = approval
        let module = WaitingAlertsModule(watcher: watcher, path: "/synthetic", reader: fixture,
            post: { fixture.messages.append($0) })
        module.start()
        await settle()
        precondition(fixture.calls == 1 && module.waitingCount == 1 && fixture.messages.isEmpty)
        fixture.block = true
        watcher.changed?()
        await settle()
        precondition(fixture.calls == 2 && fixture.readGate != nil)
        watcher.changed?()
        watcher.changed?()
        await settle()
        precondition(fixture.calls == 2)
        fixture.rows += question
        fixture.readGate?.resume(); fixture.readGate = nil
        await settle()
        precondition(module.waitingCount == 2 && fixture.messages == ["Example has a question."])
        precondition(fixture.calls == 3 && fixture.readGate != nil)
        fixture.block = false
        fixture.readGate?.resume(); fixture.readGate = nil
        await settle()
        precondition(fixture.calls == 3)
        module.refresh(report: true)
        await settle()
        precondition(fixture.calls == 4 && fixture.messages.last == "2 agents are waiting.")
        fixture.fail = true
        module.refresh(report: true)
        await settle()
        precondition(module.unavailable && fixture.messages.last == "T3 data is unavailable.")
        fixture.fail = false
        fixture.block = true
        module.refresh()
        await settle()
        let calls = fixture.calls
        let late = watcher.changed
        module.stop()
        fixture.readGate?.resume(); fixture.readGate = nil
        late?()
        await settle()
        precondition(module.waitingCount == 0 && fixture.calls == calls && watcher.stops == 1)
        module.start()
        await settle()
        precondition(fixture.calls == calls + 1 && fixture.readGate != nil)
        module.stop()
        module.start()
        await settle()
        precondition(fixture.calls == calls + 1)
        fixture.block = false
        let messages = fixture.messages.count
        fixture.readGate?.resume(); fixture.readGate = nil
        await settle()
        precondition(fixture.calls == calls + 2 && module.waitingCount == 2)
        precondition(fixture.messages.count == messages)
        module.stop()
        watcher.exists = false
        module.start()
        module.refresh(report: true)
        precondition(module.unavailable && fixture.messages.last == "T3 data is unavailable.")
        module.stop()
        precondition(!WaitingAlertsModule.command.isEnabled())
        NotchcastPreferences.shared.enabled = true
        precondition(WaitingAlertsModule.command.isEnabled())
        let entries = WaitingAlertsModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.waitingAlerts] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === WaitingAlertsModule.shared)
        print("PASS: transitions, first-read suppression, coalescing, approval/question/count text")
        print("PASS: fake watcher/reader; immediate command read; one in flight; exactly one trailing read")
        print("PASS: stop drops late result/event; missing folder; switch command gate; exact hook init; Swift 6 strict")
        print("PASS: stop/restart serializes the old read and suppresses notices on the new first read")
    }

    @MainActor static func verifyWatcher() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "waiting-watch-\(UUID().uuidString)")
        let nested = directory.appending(path: "logs")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let watcher = WaitingAlertsWatcher()
        var changes = 0
        precondition(!watcher.start(path: directory.appending(path: "missing").path) { changes += 1 })
        precondition(watcher.start(path: directory.path) { changes += 1 })
        try await Task.sleep(for: .seconds(2))
        changes = 0
        try Data("x".utf8).write(to: nested.appending(path: "log.txt"))
        try await Task.sleep(for: .seconds(3))
        precondition(changes == 0, "subfolder write must not count")
        try Data("x".utf8).write(to: directory.appending(path: "statev2.sqlite-wal"))
        for _ in 0..<50 where changes == 0 { try await Task.sleep(for: .milliseconds(100)) }
        precondition(changes > 0, "top-level write must count")
        watcher.stop()
        let stopped = changes
        try Data("y".utf8).write(to: directory.appending(path: "statev2.sqlite-wal"))
        try await Task.sleep(for: .seconds(2))
        precondition(changes == stopped, "stop must end events")
        print("PASS: real FSEvents on a temp folder: top-level write counts, subfolder write ignored, stop ends events")
    }

    static func verifyReader() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "waiting-alerts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "state.sqlite")
        let reader = WaitingAlertsReader(url: url)
        do { _ = try await reader.read(); preconditionFailure("Missing file accepted") } catch {}
        precondition(!FileManager.default.fileExists(atPath: url.path))
        var database: OpaquePointer?
        precondition(sqlite3_open(url.path, &database) == SQLITE_OK)
        sqlite3_close(database)
        do { _ = try await reader.read(); preconditionFailure("Missing schema accepted") } catch {}
        precondition(sqlite3_open(url.path, &database) == SQLITE_OK)
        let sql = """
            CREATE TABLE orchestration_v2_projection_threads
                (thread_id TEXT, title TEXT, archived_at TEXT, deleted_at TEXT);
            CREATE TABLE orchestration_v2_projection_runtime_requests
                (thread_id TEXT, kind TEXT, resolved_at TEXT);
            INSERT INTO orchestration_v2_projection_threads VALUES
                ('approval', 'Approval', NULL, NULL), ('question', 'Question', NULL, NULL),
                ('both', 'Both', NULL, NULL), ('resolved', 'Resolved', NULL, NULL),
                ('archived', 'Archived', 'date', NULL), ('deleted', 'Deleted', NULL, 'date'),
                ('future', 'Future', NULL, NULL);
            INSERT INTO orchestration_v2_projection_runtime_requests VALUES
                ('approval', 'command', NULL), ('approval', 'command', NULL),
                ('question', 'user_input', NULL), ('both', 'user_input', NULL), ('both', 'command', NULL),
                ('resolved', 'command', 'date'), ('resolved', 'user_input', 'date'),
                ('archived', 'command', NULL), ('deleted', 'user_input', NULL),
                ('orphan', 'command', NULL), ('future', 'future_kind', NULL);
            """
        precondition(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let rows = try await reader.read()
        precondition(rows == [WaitingAlert(id: "approval", title: "Approval", kind: .approval),
                              WaitingAlert(id: "both", title: "Both", kind: .approval),
                              WaitingAlert(id: "future", title: "Future", kind: .approval),
                              WaitingAlert(id: "question", title: "Question", kind: .question)])
        print("PASS: temp SQLite pending/resolved rows; archived/deleted/orphan excluded; grouped; approval wins")
        print("PASS: missing file not created; schema-missing database throws; unknown kind is approval")
    }
}
