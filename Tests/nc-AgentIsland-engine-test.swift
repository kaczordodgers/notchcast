// notchcast-sources: -strict-concurrency=complete -lsqlite3 Tinycast/Features/AgentIsland/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentIsland/Service/*.swift Tinycast/Features/AgentThreads/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentThreads/Service/*.swift Tinycast/Features/AgentThreads/AgentThreadsModule.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Features/OpenBotAgents/Model/*.swift Tinycast/Features/OpenBotAgents/Service/*.swift
// notchcast-reads: Tinycast/Resources/Notchcast.xcstrings
import Foundation

@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }
enum TestFeature { case agentThreads, openBotAgents, agentIsland }
enum TestTone { case neutral }
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
    var on = false
    func isOn(_ feature: TestFeature) -> Bool { on }
}
@MainActor final class TestAppIndex { func refreshNotchcastCommands() {} }
@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = TestAppIndex()
    func showMessage(_ text: String, tone: TestTone) {}
}
@MainActor enum NotchcastCore {
    static let agentThreads = AgentThreadsModule(availabilityChanged: { AppCore.shared.appIndex.refreshNotchcastCommands() })
    static let openBotAgents = OpenBotAgentsModule()
    static let agentIsland = AgentIslandModule(threads: agentThreads, bots: openBotAgents,
        enabled: { NotchcastPreferences.shared.isOn($0 == .t3 ? .agentThreads : .openBotAgents) },
        availabilityChanged: { AppCore.shared.appIndex.refreshNotchcastCommands() })
}

private struct Projects: AgentThreadProjectReading {
    func projects() async throws -> [AgentThreadProject] { [.init(id: "demo", title: "Demo")] }
}
private struct Runner: AgentThreadRunning {
    func run(arguments: [String]) async throws -> Data {
        Data("""
        [{"threadId":"sample","title":"Example","status":"running",
        "link":"https://example.com/thread","updatedAt":"1970-01-01T00:01:40Z"}]
        """.utf8)
    }
}
private struct Transport: OpenBotTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) { (Data("[]".utf8), 200) }
}

@MainActor private final class BotFixture {
    var waiting = false
    var requests = 0
}
private struct RestartTransport: OpenBotTransport {
    let fixture: BotFixture
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let waiting = await MainActor.run {
            fixture.requests += 1
            return fixture.waiting
        }
        if request.url?.lastPathComponent == "pending" {
            return (Data((waiting ? #"{"approvals":[{}]}"# : "{}").utf8), 200)
        }
        return (Data(#"[{"id":"sample","name":"Example"}]"#.utf8), 200)
    }
}

@MainActor private final class PassCounter {
    var passes = 0
    var cancellations = 0
}
private struct CountingRunner: AgentThreadRunning {
    let counter: PassCounter
    func run(arguments: [String]) async throws -> Data {
        await MainActor.run { counter.passes += 1 }
        do {
            try await Task.sleep(for: .milliseconds(80))
        } catch {
            await MainActor.run { counter.cancellations += 1 }
            throw error
        }
        return Data("[]".utf8)
    }
}

@main struct AgentIslandTest {
    @MainActor static func main() async throws {
        let now = Date(timeIntervalSince1970: 100)
        func row(_ phase: AgentThread.Phase, _ id: String = "a", date: Date? = nil) -> AgentThread {
            AgentThread(id: id, title: id, project: "Demo", model: "Example", phase: phase,
                        pendingCount: 2, link: URL(string: "https://example.com/\(id)")!,
                        updatedAt: date ?? now, settled: true)
        }
        var engine = AgentIslandEngine()
        func evaluate(_ rows: [AgentThread], _ pending: [String: OpenBotPending] = [:],
                      date: Date? = nil, t3: Bool = true, bot: Bool = true) -> AgentIslandEngine.Presentation {
            engine.update(threads: rows, pending: pending, t3Enabled: t3, openBotEnabled: bot, now: date ?? now)
            return engine.presentation
        }
        let mappings: [(AgentThread.Phase, AgentIslandEngine.Mode)] = [
            (.waitingForApproval, .approval(2)), (.waitingForInput, .question(1)),
            (.starting, .working(names: ["a"], total: 1)), (.running, .working(names: ["a"], total: 1)),
            (.completed, .finished("a")), (.failed, .failed("a")), (.stale, .idle)
        ]
        for (phase, expected) in mappings { precondition(evaluate([row(phase)]).t3 == expected) }
        let ordered: [AgentThread.Phase] = [.waitingForApproval, .waitingForInput, .failed, .running, .completed, .stale]
        for index in ordered.indices {
            let rows = ordered[index...].enumerated().map { row($0.element, String($0.offset)) }
            let result = evaluate(rows)
            let expected = evaluate([rows[0]]).t3
            precondition(result.t3 == expected)
        }
        let workers = (0..<5).map { row(.running, String($0)) }
        precondition(evaluate(workers).t3 == .working(names: ["0", "1", "2"], total: 5))
        precondition(evaluate(workers.reversed()) == evaluate(workers))
        precondition(evaluate([row(.completed)]).t3 == .finished("a"))
        precondition(evaluate([row(.completed)], date: now.addingTimeInterval(5.199)).t3 == .finished("a"))
        precondition(evaluate([row(.completed)], date: now.addingTimeInterval(5.2)).t3 == .idle)
        precondition(evaluate([row(.completed)], date: now.addingTimeInterval(-1)).t3 == .idle)
        engine = AgentIslandEngine()
        precondition(evaluate([row(.completed, date: now.addingTimeInterval(-31))]).t3 == .idle)
        precondition(evaluate([row(.running)]).t3 == .working(names: ["a"], total: 1))
        let late = now.addingTimeInterval(15)
        precondition(evaluate([row(.completed)], date: late).t3 == .finished("a"))
        precondition(evaluate([row(.completed)], date: late.addingTimeInterval(5.199)).t3 == .finished("a"))
        precondition(evaluate([row(.completed)], date: late.addingTimeInterval(5.2)).t3 == .idle)
        engine = AgentIslandEngine()
        let recent = row(.completed, date: now.addingTimeInterval(-20))
        precondition(evaluate([recent]).t3 == .idle)
        precondition(evaluate([recent], date: now.addingTimeInterval(5.2)).t3 == .idle)
        engine = AgentIslandEngine()
        let firstSight = row(.completed, date: now.addingTimeInterval(-4))
        precondition(evaluate([firstSight]).t3 == .finished("a"))
        precondition(evaluate([firstSight], date: now.addingTimeInterval(1.2)).t3 == .idle)
        for waitingPhase: AgentThread.Phase in [.waitingForApproval, .waitingForInput] {
            engine = AgentIslandEngine()
            _ = evaluate([row(.running)])
            _ = evaluate([row(waitingPhase)])
            precondition(evaluate([row(.completed)], date: late).t3 == .finished("a"))
            precondition(evaluate([row(.completed)], date: late.addingTimeInterval(5.2)).t3 == .idle)
            engine = AgentIslandEngine()
            _ = evaluate([row(waitingPhase)])
            precondition(evaluate([row(.completed)], date: late).t3 == .finished("a"))
        }
        let newest = row(.completed, "new", date: now.addingTimeInterval(1))
        precondition(evaluate([recent, newest], date: now.addingTimeInterval(1)).t3 == .finished("new"))
        let failed = row(.failed)
        precondition(evaluate([failed], date: now.addingTimeInterval(500)).t3 == .failed("a"))
        engine.dismissFailed(failed)
        precondition(evaluate([failed]).t3 == .idle)
        precondition(evaluate([failed], t3: false).t3 == .idle)
        precondition(evaluate([failed]).t3 == .idle)
        precondition(evaluate([]).t3 == .idle)
        precondition(evaluate([failed]).t3 == .idle)
        precondition(evaluate([row(.failed, date: now.addingTimeInterval(1))]).t3 == .failed("a"))
        let decoder = JSONDecoder()
        func pending(_ json: String) throws -> OpenBotPending {
            try decoder.decode(OpenBotPending.self, from: Data(json.utf8))
        }
        let prompts = try pending(#"{"prompts":[{"questions":[]},{"questions":[]}] }"#)
        let approval = try pending(#"{"approvals":[{}],"browserTakeovers":[{}],"prompts":[{}]}"#)
        precondition(evaluate([], ["b": prompts]).openBot == .question(2))
        precondition(evaluate([], ["b": approval]).openBot == .approval(2))
        let takeover = try pending(#"{"browserTakeovers":[{}]}"#)
        precondition(evaluate([], ["b": takeover]).openBot == .approval(1))
        let combined = evaluate(workers + [row(.waitingForApproval)], ["b": approval])
        precondition(combined.waiting == 5 && combined.working == 5)
        precondition(combined.message == .counts(waiting: 5, working: 5))
        let absent = evaluate(workers, ["b": approval], t3: false, bot: false)
        precondition(absent == .init() && absent.message == .idle)
        let module = NotchcastCore.agentIsland
        module.start()
        precondition(module.presentation == .init())
        precondition(!AgentIslandModule.command.isEnabled())
        NotchcastPreferences.shared.on = true
        precondition(AgentIslandModule.command.isEnabled())
        precondition(module.openItem(source: .t3, thread: failed) == failed.link)
        precondition(module.openItem(source: .openBot, thread: failed) == nil)
        module.stop()
        for _ in 0..<10 { await Task.yield() }
        precondition(module.presentation == .init())
        let state = AgentThreadsState(runner: Runner(), projects: Projects(), now: { now })
        let threads = AgentThreadsModule(state: state)
        let bots = OpenBotAgentsModule(service: .init(transport: Transport(), credentials: {
            try OpenBotCredentials(url: "http://127.0.0.1:12345", token: "synthetic")
        }))
        let observed = AgentIslandModule(threads: threads, bots: bots, enabled: { _ in true },
                                        now: { now }, availabilityChanged: {})
        observed.start()
        precondition(state.status == .idle && bots.agents.isEmpty)
        threads.start()
        bots.start()
        await state.waitUntilIdle()
        await bots.waitUntilIdle()
        for _ in 0..<20 { await Task.yield() }
        precondition(observed.presentation.working == 1)
        var refreshed = false
        observed.refresh { message in
            precondition(message == .counts(waiting: 0, working: 1))
            refreshed = true
        }
        while !refreshed { await Task.yield() }
        observed.stop()
        threads.stop()
        bots.stop()
        for _ in 0..<20 { await Task.yield() }
        precondition(observed.presentation == .init())
        let counter = PassCounter()
        let countedState = AgentThreadsState(runner: CountingRunner(counter: counter), projects: Projects())
        let countedThreads = AgentThreadsModule(state: countedState)
        let counted = AgentIslandModule(threads: countedThreads, bots: bots, enabled: { $0 == .t3 },
                                        availabilityChanged: {})
        countedThreads.start()
        counted.start()
        counted.setVisible(false)
        counted.stop()
        await countedState.waitUntilIdle()
        precondition(counter.passes == 1 && counter.cancellations == 0)
        counted.start()
        var foreignDelivered = false
        countedState.refresh { _ in foreignDelivered = true }
        counted.stop()
        await countedState.waitUntilIdle()
        precondition(foreignDelivered && counter.cancellations == 0)
        counted.start()
        foreignDelivered = false
        countedState.refresh { _ in foreignDelivered = true }
        var joined = false
        let beforeJoin = counter.passes
        counted.refresh { _ in joined = true }
        while !joined { await Task.yield() }
        precondition(foreignDelivered && counter.passes == beforeJoin + 1 && counter.cancellations == 0)
        counted.setVisible(true)
        while countedState.status != .ready { await Task.yield() }
        let beforeVisibleRefresh = counter.passes
        var visibleDone = false
        counted.refresh { _ in visibleDone = true }
        while !visibleDone { await Task.yield() }
        // Agent Threads polls every 15 s; one second without a new pass proves no extra round followed.
        try await Task.sleep(for: .seconds(1))
        precondition(counter.passes == beforeVisibleRefresh + 1,
                     "Passes: \(counter.passes), before refresh: \(beforeVisibleRefresh)")
        counted.stop()
        countedThreads.stop()
        let fixture = BotFixture()
        let restartedBots = OpenBotAgentsModule(service: .init(transport: RestartTransport(fixture: fixture),
            credentials: { try OpenBotCredentials(url: "http://127.0.0.1:12345", token: "synthetic") }))
        let restarted = AgentIslandModule(threads: threads, bots: restartedBots, enabled: { $0 == .openBot },
                                         availabilityChanged: {})
        restartedBots.start()
        await restartedBots.waitUntilIdle()
        restarted.start()
        restarted.setVisible(true)
        restartedBots.stop()
        restartedBots.start()
        await restartedBots.waitUntilIdle()
        fixture.waiting = true
        let beforeBotRefresh = fixture.requests
        var botDone = false
        restarted.refresh { message in
            precondition(message == .counts(waiting: 1, working: 0))
            precondition(fixture.requests >= beforeBotRefresh + 2)
            botDone = true
        }
        while !botDone { await Task.yield() }
        restarted.stop()
        restartedBots.stop()
        let catalogData = try Data(contentsOf: URL(filePath: "Tinycast/Resources/Notchcast.xcstrings"))
        let catalog = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        func catalogText(_ path: [String]) -> String? {
            path.reduce(catalog as Any?) { value, key in (value as? [String: Any])?[key] } as? String
        }
        let localePath = ["strings", "%lld waiting, %lld working.", "localizations"]
        for locale in ["es", "fr", "pt", "ru"] {
            let base = localePath + [locale, "substitutions", "working", "variations", "plural"]
            let one = catalogText(base + ["one", "stringUnit", "value"])
            let many = catalogText(base + ["many", "stringUnit", "value"])
            precondition(one != nil && many != nil && one != many)
        }
        let russian = localePath + ["ru", "substitutions", "waiting", "variations", "plural"]
        precondition(catalogText(russian + ["one", "stringUnit", "value"])
                     != catalogText(russian + ["many", "stringUnit", "value"]))
        print("PASS: inflected summary words belong to their own count's plural variant")
        print("PASS: approval/waiting transitions finish; first-sight completion expires at source time + 5.2s")
        print("PASS: dismissed failure survives source off/on; visible command refreshes restarted OpenBot")
        print("PASS: invisible stop/refresh preserve foreign refresh completion; zero forwarded activity changes")
        print("PASS: visible status refresh runs exactly one T3 pass and no extra round after it")
        print("PASS: late completion gets 5.2 seconds from first sight; stale completion stays hidden")
        print("PASS: every source mapping, priority, stable ordering, name cap and combined summary/message choice")
        print("PASS: injected 5.2-second window, persistent failure, dismissal and changed failure")
        print("PASS: Swift 6 complete concurrency, hook-shaped MainActor init, switch gate and stop")
        print("PASS: observation receives synthetic source changes; start does no I/O; refresh awaits both sources")
    }
}
