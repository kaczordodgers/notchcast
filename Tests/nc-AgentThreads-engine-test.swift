// notchcast-sources: -lsqlite3 Tinycast/Features/AgentThreads/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentThreads/AgentThreadsModule.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Features/AgentThreads/Service/*.swift
// notchcast-reads: Tinycast/Features/AgentThreads/AgentThreadsModule.swift
// notchcast-sources: Tinycast/Features/AgentThreads/AgentThreadsModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
import Foundation
import SQLite3

enum TestFeature { case agentThreads }
typealias NotchcastFeature = TestFeature
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
    func isOn(_ feature: TestFeature) -> Bool { true }
}
@MainActor final class AppCore {}

private struct FakeProjects: AgentThreadProjectReading {
    var values = [AgentThreadProject(id: "demo", title: "Demo")]
    func projects() async throws -> [AgentThreadProject] { values }
}

@MainActor
private final class CallCounter {
    var show = 0
    var replacement: Data?
    var lists: [[String]] = []
}

private struct FakeRunner: AgentThreadRunning {
    var failure: AgentThreadFailure?
    var delay = false
    var listData: Data?
    var counter: CallCounter?
    var failedProject: String?
    var failedShow = false
    func run(arguments: [String]) async throws -> Data {
        if delay { try? await Task.sleep(for: .milliseconds(80)) }
        if let failure { throw failure }
        if arguments.contains("show") {
            await MainActor.run { counter?.show += 1 }
            if failedShow { throw AgentThreadFailure.commandFailed }
            return Data(#"{"thread":{"status":"waiting","pendingRequestCount":2}}"#.utf8)
        }
        if arguments.contains("list") {
            await MainActor.run { counter?.lists.append(arguments) }
            if let failedProject, arguments.contains(failedProject) { throw AgentThreadFailure.commandFailed }
        }
        if let replacement = await counter?.replacement { return replacement }
        if let listData { return listData }
        return Data("""
        [{"threadId":"sample","title":"Example","projectId":"demo","model":"Example Model",
        "status":"running","link":"https://example.com/thread","updatedAt":"2026-01-01T12:00:00Z"}]
        """.utf8)
    }
}

@main
struct AgentThreadsTest {
    @MainActor
    static func main() async throws {
        let runner = FakeRunner()
        let environment = AgentThreadRunner.environment(for: "/opt/homebrew/bin/t3", inheriting: ["KEEP": "yes"])
        precondition(environment == ["PATH": "/opt/homebrew/bin:/usr/bin:/bin", "KEEP": "yes"])
        let data = try await runner.run(arguments: [])
        let rows = try AgentThreadParser.list(data, project: "Demo")
        precondition(rows.count == 1 && rows[0].title == "Example" && rows[0].project == "Demo")
        let envelope = Data("{\"threads\":".utf8) + data + Data("}".utf8)
        let enveloped = try AgentThreadParser.list(envelope, project: "Demo")
        precondition(enveloped == rows)
        let statuses: [(String?, AgentThread.Phase)] = [
            ("idle", .stale), (nil, .stale), ("preparing", .starting), ("queued", .starting),
            ("starting", .starting), ("running", .running), ("waiting", .waitingForInput),
            ("completed", .completed), ("failed", .failed), ("interrupted", .failed),
            ("cancelled", .failed), ("rolled_back", .failed), ("unknown", .stale)
        ]
        for (status, expected) in statuses {
            let statusJSON = status.map { "\"\($0)\"" } ?? "null"
            let fixture = Data("""
            [{"threadId":"sample","status":\(statusJSON),
            "link":"http://127.0.0.1:3773/demo/sample","updatedAt":"2026-01-01T12:00:00Z"}]
            """.utf8)
            let parsed = try AgentThreadParser.list(fixture)
            precondition(parsed.count == 1 && parsed[0].phase == expected)
        }
        let threadLink = "t3-thread:" + "//demo/sample"
        let missing = Data("""
        [{"threadId":"sample","link":"\(threadLink)","updatedAt":"2026-01-01T12:00:00Z"}]
        """.utf8)
        let missingRows = try AgentThreadParser.list(missing)
        precondition(missingRows.first?.phase == .stale)
        for bad in [#"{"threadId":"","link":"https://example.com","updatedAt":"2026-01-01T12:00:00Z"}"#,
                    #"{"threadId":"bad","link":"http://example.com","updatedAt":"2026-01-01T12:00:00Z"}"#,
                    #"{"threadId":"bad","link":"https://example.com","updatedAt":"invalid"}"#,
                    #"{"threadId":42}"#] {
            let mixed = Data("[\(bad),".utf8) + data.dropFirst()
            let parsed = try AgentThreadParser.list(mixed, project: "Demo")
            precondition(parsed == rows)
        }
        precondition(AgentThreadParser.phase("future-status") == .stale)
        let detail = try await runner.run(arguments: ["show"])
        let waiting = try AgentThreadParser.show(detail, updating: rows[0])
        precondition(waiting.pendingCount == 2 && waiting.phase == .waitingForApproval)
        let input = try AgentThreadParser.show(
            Data(#"{"thread":{"status":"waiting","pendingRequestCount":0}}"#.utf8), updating: rows[0])
        precondition(input.phase == .waitingForInput)
        let now = rows[0].updatedAt
        let finished = AgentThread(id: "finished", title: "", project: "", model: "", phase: .completed,
                                   pendingCount: 0, link: rows[0].link, updatedAt: now, settled: true)
        precondition(AgentThreadParser.select([rows[0], finished, waiting], now: now).first?.phase.waiting == true)
        precondition(AgentThreadParser.select([finished], now: now.addingTimeInterval(1800)).count == 1)
        precondition(AgentThreadParser.select([finished], now: now.addingTimeInterval(1801)).isEmpty)
        do {
            _ = try AgentThreadParser.list(Data("invalid".utf8))
            preconditionFailure("Bad JSON accepted")
        } catch {}
        do {
            _ = try await AgentThreadRunner(paths: []).run(arguments: [])
            preconditionFailure("Missing CLI accepted")
        } catch { precondition(error as? AgentThreadFailure == .unavailable) }
        do {
            _ = try await AgentThreadRunner(paths: ["/bin/sleep"], timeout: .milliseconds(30))
                .run(arguments: ["2"])
            preconditionFailure("Timeout not enforced")
        } catch { precondition(error as? AgentThreadFailure == .timeout) }
        let state = AgentThreadsState(runner: runner, projects: FakeProjects(), now: { now })
        state.start()
        await state.waitUntilIdle()
        precondition(state.status == .ready && state.threads.first?.pendingCount == 2)
        state.refresh()
        state.setActive(false)
        precondition(state.status == .ready)
        state.stop()
        state.refresh()
        precondition(state.status == .idle && state.threads.isEmpty)
        let unavailable = AgentThreadsState(runner: FakeRunner(failure: .unavailable), projects: FakeProjects())
        unavailable.start()
        await unavailable.waitUntilIdle()
        precondition(unavailable.status == .unavailable)
        precondition(unavailable.waitingMessage == String(localized: "T3 CLI not found."))
        let timeout = AgentThreadsState(runner: FakeRunner(failure: .timeout), projects: FakeProjects())
        timeout.start()
        await timeout.waitUntilIdle()
        precondition(timeout.status == .failed)
        precondition(timeout.waitingMessage == String(localized: "Could not refresh agent threads."))
        let late = AgentThreadsState(runner: FakeRunner(delay: true), projects: FakeProjects())
        late.start()
        await Task.yield()
        late.setActive(false)
        precondition(late.status == .idle)
        try await Task.sleep(for: .milliseconds(150))
        precondition(late.status == .idle && late.threads.isEmpty)
        let counter = CallCounter()
        let list = Data("""
        [{"threadId":"idle-example","status":"idle","link":"https://example.com/idle","updatedAt":"2026-01-01T12:00:00Z"},
        {"threadId":"done-example","status":"completed","link":"https://example.com/done","updatedAt":"2026-01-01T12:00:00Z"},
        {"threadId":"active-example","status":"starting","link":"https://example.com/active","updatedAt":"2026-01-01T12:00:00Z"},
        {"threadId":"running-example","status":"running","link":"https://example.com/running","updatedAt":"2026-01-01T12:00:00Z"},
        {"threadId":"waiting-example","status":"waiting","link":"https://example.com/waiting","updatedAt":"2026-01-01T12:00:00Z"}]
        """.utf8)
        let counted = AgentThreadsState(runner: FakeRunner(listData: list, counter: counter),
                                        projects: FakeProjects(), now: { now })
        counted.start()
        await counted.waitUntilIdle()
        precondition(counted.status == .ready && counter.show == 3)
        counter.replacement = Data("""
        [{"threadId":"new","status":"waiting","link":"https://example.com/new","updatedAt":"2026-01-01T12:00:00Z"}]
        """.utf8)
        var opened: URL?
        counted.refresh { refreshed in
            precondition(refreshed.waitingMessage == nil)
            opened = refreshed.threads.first(where: { $0.phase.waiting })?.link
        }
        await counted.waitUntilIdle()
        precondition(opened == URL(string: "https://example.com/new"))
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "nc-agent-threads-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let databaseURL = URL(filePath: scratch).appending(path: "projects.sqlite")
        var database: OpaquePointer?
        precondition(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        precondition(sqlite3_exec(database, """
            CREATE TABLE projection_projects (project_id TEXT PRIMARY KEY, title TEXT NOT NULL,
                deleted_at TEXT, archived_at TEXT);
            INSERT INTO projection_projects VALUES ('demo', 'Demo', NULL, NULL),
                ('other', 'Other', NULL, NULL), ('deleted', 'Deleted', 'date', NULL),
                ('archived', 'Archived', NULL, 'date');
            """, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let projects = AgentThreadProjects(url: databaseURL)
        let discovered = try await projects.projects()
        precondition(Set(discovered.map(\.id)) == ["demo", "other"])
        let partialCounter = CallCounter()
        let partial = AgentThreadsState(runner: FakeRunner(counter: partialCounter, failedProject: "other",
                                                         failedShow: true), projects: projects, now: { now })
        partial.start()
        await partial.waitUntilIdle()
        precondition(partial.status == .ready && partial.threads.count == 1)
        precondition(partial.threads[0].project == "Demo" && partial.threads[0].phase == .running)
        precondition(Set(partialCounter.lists) == Set([
            ["thread", "list", "--project", "demo", "--json"],
            ["thread", "list", "--project", "other", "--json"]]))
        let missingDB = AgentThreadsState(runner: runner,
            projects: AgentThreadProjects(url: URL(filePath: scratch).appending(path: "missing.sqlite")))
        missingDB.start()
        await missingDB.waitUntilIdle()
        precondition(missingDB.status == .unavailable)
        precondition(!FileManager.default.fileExists(atPath: URL(filePath: scratch).appending(path: "missing.sqlite").path))
        precondition(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        precondition(sqlite3_exec(database, "DROP TABLE projection_projects", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let missingTable = AgentThreadsState(runner: runner, projects: projects)
        missingTable.start()
        await missingTable.waitUntilIdle()
        precondition(missingTable.status == .failed)
        var availabilityCalls = 0
        let module = AgentThreadsModule(state: partial, availabilityChanged: { availabilityCalls += 1 })
        module.start()
        module.stop()
        precondition(availabilityCalls == 2)
        let entries = AgentThreadsModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.agentThreads] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === AgentThreadsModule.shared)
        print("PASS: registration entry")
        print("PASS: SQLite active projects only; missing file/table; per-project arguments and names")
        print("PASS: partial list failure; show failure preserves phase; availability changed on start and stop")
        print("PASS: child PATH preserves environment; refresh completion selects waiting link; failure messages")
        let catalog = try String(contentsOfFile:
            "Tinycast/Features/AgentThreads/AgentThreadsModule.swift", encoding: .utf8)
        precondition(catalog.components(separatedBy: "isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) }")
            .count == 3)
        print("PASS: real statuses including null, loopback link, dropped bad rows, show calls = 3, cancellation idle/ready")
        print("PASS: waiting order, finished window, missing CLI, bad JSON, timeout, command gates")
    }
}
