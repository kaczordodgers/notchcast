import Foundation

private struct FakeRunner: AgentThreadRunning {
    var failure: AgentThreadFailure?
    var delay = false
    func run(arguments: [String]) async throws -> Data {
        if delay { try? await Task.sleep(for: .milliseconds(80)) }
        if let failure { throw failure }
        if arguments.contains("show") {
            return Data(#"{"thread":{"status":"running","pendingRequestCount":2}}"#.utf8)
        }
        return Data("""
        [{"threadId":"sample","title":"Example","project":"Demo","model":"Example Model",
        "status":"running","link":"https://example.com/thread","updatedAt":"2026-01-01T12:00:00Z"}]
        """.utf8)
    }
}

@main
struct AgentThreadsTest {
    @MainActor
    static func main() async throws {
        let runner = FakeRunner()
        let data = try await runner.run(arguments: [])
        let rows = try AgentThreadParser.list(data)
        precondition(rows.count == 1 && rows[0].title == "Example" && rows[0].project == "Demo")
        let envelope = Data("{\"threads\":".utf8) + data + Data("}".utf8)
        let enveloped = try AgentThreadParser.list(envelope)
        precondition(enveloped == rows)
        for phase in AgentThread.Phase.allCases {
            precondition(AgentThreadParser.phase(phase.rawValue) == phase)
        }
        precondition(AgentThreadParser.phase("future-status") == .stale)
        let detail = try await runner.run(arguments: ["show"])
        let waiting = try AgentThreadParser.show(detail, updating: rows[0])
        precondition(waiting.pendingCount == 2 && waiting.phase == .waitingForApproval)
        let input = try AgentThreadParser.show(
            Data(#"{"thread":{"status":"waitingForInput","pendingRequestCount":1}}"#.utf8), updating: rows[0])
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
        let state = AgentThreadsState(runner: runner, now: { now })
        state.start()
        await state.waitUntilIdle()
        precondition(state.status == .ready && state.threads.first?.pendingCount == 2)
        state.stop()
        state.refresh()
        precondition(state.status == .idle && state.threads.isEmpty)
        let unavailable = AgentThreadsState(runner: FakeRunner(failure: .unavailable))
        unavailable.start()
        await unavailable.waitUntilIdle()
        precondition(unavailable.status == .unavailable)
        let timeout = AgentThreadsState(runner: FakeRunner(failure: .timeout))
        timeout.start()
        await timeout.waitUntilIdle()
        precondition(timeout.status == .failed)
        let late = AgentThreadsState(runner: FakeRunner(delay: true))
        late.start()
        await Task.yield()
        late.stop()
        try await Task.sleep(for: .milliseconds(150))
        precondition(late.status == .idle && late.threads.isEmpty)
        let catalog = try String(contentsOfFile:
            "Tinycast/Features/AgentThreads/AgentThreadsModule.swift", encoding: .utf8)
        precondition(catalog.components(separatedBy: "isEnabled: { NotchcastPreferences.shared.isOn(.agentThreads) }")
            .count == 3)
        print("PASS: parsing, all phases, waiting order, finished window, missing CLI, bad JSON, timeout, stop, command gates")
    }
}
