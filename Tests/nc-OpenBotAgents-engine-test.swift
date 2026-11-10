// notchcast-sources: Tinycast/Features/OpenBotAgents/Model/*.swift
// notchcast-sources: Tinycast/Features/OpenBotAgents/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/OpenBotAgents/OpenBotAgentsModule+Command.swift
// notchcast-sources: Tinycast/Features/OpenBotAgents/OpenBotAgentsModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: -strict-concurrency=complete -warnings-as-errors
import Foundation
import Synchronization

@MainActor
final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = false
    func isOn(_ feature: NotchcastFeature) -> Bool {
        precondition(feature == .openBotAgents)
        return enabled
    }
}

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

enum DialogTone { case neutral }

@MainActor final class AppCore {}

final class FixtureTransport: OpenBotTransport {
    let responses: Mutex<[(String, Int)]>
    let requests = Mutex<[URLRequest]>([])
    let delay: Bool
    let error: URLError?
    /// Answers once the queue is empty, so timer-driven passes under load cannot exhaust it.
    let fallback: (@Sendable (URLRequest) -> (String, Int))?

    init(_ responses: [(String, Int)], delay: Bool = false, error: URLError? = nil,
         fallback: (@Sendable (URLRequest) -> (String, Int))? = nil) {
        self.responses = Mutex(responses)
        self.delay = delay
        self.error = error
        self.fallback = fallback
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.withLock { $0.append(request) }
        if delay { try? await Task.sleep(for: .milliseconds(100)) }
        if let error { throw error }
        let queued = responses.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        guard let response = queued ?? fallback?(request) else { fatalError("Fixture queue empty") }
        return (Data(response.0.utf8), response.1)
    }
}

@main
struct OpenBotTests {
    static let bots = #"[{"id":"fixture-bot","name":"Paper Kite","routines":[],"extra":true}]"#
    static let empty = #"{"prompts":[],"approvals":[],"browserTakeovers":[]}"#

    static func service(_ transport: FixtureTransport) -> OpenBotService {
        OpenBotService(transport: transport, credentials: {
            try OpenBotCredentials(url: "http://127.0.0.1:8765", token: "synthetic-secret")
        })
    }

    @MainActor
    static func expectFailure(_ expected: OpenBotFailure, _ action: () async throws -> Void) async {
        do { try await action(); fatalError("Expected failure") } catch {
            precondition(error as? OpenBotFailure == expected)
            precondition(!String(describing: error).contains("synthetic-secret"))
        }
    }

    @MainActor
    static func main() async throws {
        let transport = FixtureTransport([(bots, 200), (empty, 200),
            ("""
                {"prompts":[{"questions":[{"question":"Pick a paper color"}]},{"questions":[]}],
                "approvals":[{}],"browserTakeovers":[{}]}
                """, 200)])
        let client = service(transport)
        let agents = try await client.agents()
        precondition(agents.first?.name == "Paper Kite")
        let none = try await client.pending(agent: "fixture-bot")
        precondition(!none.isWaiting)
        let pending = try await client.pending(agent: "fixture-bot")
        precondition(pending.prompts.count == 2 && pending.approvals.count == 1 && pending.browserTakeovers.count == 1)
        precondition(pending.prompts[0].questions[0].question == "Pick a paper color")
        for routines in ["", ",\"routines\":null"] {
            let fixture = "[{\"id\":\"fixture-bot\",\"name\":\"Paper Kite\"\(routines)}]"
            let decoded = try await service(FixtureTransport([(fixture, 200)])).agents()
            precondition(decoded.count == 1 && decoded[0].routines.isEmpty)
        }
        for fixture in ["{}", #"{"prompts":null,"approvals":null,"browserTakeovers":null}"#] {
            let decoded = try await service(FixtureTransport([(fixture, 200)])).pending(agent: "fixture-bot")
            precondition(!decoded.isWaiting)
        }
        let tolerant = #"{"prompts":[{},{"questions":null},{"questions":[{}, {"question":null}]}]}"#
        let decoded = try await service(FixtureTransport([(tolerant, 200)])).pending(agent: "fixture-bot")
        precondition(decoded.prompts.count == 3 && decoded.isWaiting)
        precondition(decoded.prompts[0].questions.isEmpty && decoded.prompts[1].questions.isEmpty)
        precondition(decoded.prompts[2].questions.count == 2)
        precondition(decoded.prompts[2].questions.allSatisfy { $0.question == nil })
        let lossy = """
            {"prompts":[null,{"questions":[null,{"question":42},{"question":"Keep"}]}],
            "approvals":[null,{}],"browserTakeovers":[null,{}]}
            """
        let kept = try JSONDecoder().decode(OpenBotPending.self, from: Data(lossy.utf8))
        precondition(kept.isWaiting && kept.prompts.count == 1)
        precondition(kept.prompts[0].questions.map(\.question) == ["Keep"])
        precondition(kept.approvals.count == 1 && kept.browserTakeovers.count == 1)
        let routines = #"{"routines":[null,{"id":42},{"id":"paper","name":"Keep","active":true}]}"#
        let keptAgent = try JSONDecoder().decode(OpenBotAgent.self, from: Data(routines.utf8))
        precondition(keptAgent.routines.count == 1 && keptAgent.routines[0].name == "Keep")
        for answer in ["null", "{}", "[]", "42", "true", #""Paper answer""#] {
            let fixture = "{\"id\":\"fixture-delivery\",\"status\":\"completed\",\"answer\":\(answer)}"
            let delivery = try await service(FixtureTransport([(fixture, 200)]))
                .delivery(agent: "fixture-bot", id: "fixture-delivery")
            precondition(delivery.answer == (answer == #""Paper answer""# ? "Paper answer" : nil))
        }
        await expectFailure(.malformed) { _ = try await service(FixtureTransport([("{}", 200)])).agents() }
        await expectFailure(.malformed) {
            _ = try await service(FixtureTransport([("[]", 200)])).pending(agent: "fixture-bot")
        }
        let statuses: [(String, OpenBotDelivery.Status)] = [
            ("queued", .queued), ("pending", .pending), ("running", .running), ("completed", .completed),
            ("failed", .failed), ("interrupted", .interrupted), ("cancelled", .cancelled), ("future", .unknown)]
        for (status, expected) in statuses {
            let fixture = "{\"id\":\"fixture-delivery\",\"status\":\"\(status)\",\"answer\":null}"
            let delivery = try await service(FixtureTransport([(fixture, 200)]))
                .delivery(agent: "fixture-bot", id: "fixture-delivery")
            precondition(delivery.status == expected, "\(status)")
            precondition(delivery.status.hasEnded == ["completed", "failed", "interrupted", "cancelled"].contains(status))
        }
        let receipt = """
            {"messageId":"fixture-message","deliveries":[
            {"id":"fixture-delivery","recipientAgentId":"fixture-bot","status":"queued"}]}
            """
        let sends = FixtureTransport([(receipt, 202), (receipt, 202)])
        for _ in 0..<2 { _ = try await service(sends).send(agent: "fixture-bot", text: "Hello paper") }
        let bodies = try sends.requests.withLock { requests in
            try requests.map { request -> [String: String] in
                precondition(request.value(forHTTPHeaderField: "Origin") == nil)
                return try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            }
        }
        precondition(bodies[0]["clientMessageId"] != bodies[1]["clientMessageId"])
        precondition(UUID(uuidString: bodies[0]["clientMessageId"]!) != nil)
        for (code, failure) in [(400, OpenBotFailure.input), (401, .unauthorized), (403, .forbidden),
            (404, .missing), (405, .method), (409, .conflict), (413, .oversized), (415, .mediaType),
            (429, .rateLimited), (500, .server), (503, .server), (302, .unexpected)] {
            let fake = FixtureTransport(Array(repeating: (#"{"error":"synthetic-secret"}"#, code), count: 2))
            await expectFailure(failure) { _ = try await service(fake).agents() }
            precondition(fake.requests.withLock { $0.count } == (code == 401 ? 2 : 1))
        }
        let reads = Mutex(0)
        let retry = FixtureTransport([("", 401), (bots, 200)])
        let rotated = OpenBotService(transport: retry, credentials: {
            let number = reads.withLock { $0 += 1; return $0 }
            return try OpenBotCredentials(url: "http://127.0.0.1:8765", token: "fixture-\(number)")
        })
        _ = try await rotated.agents()
        precondition(reads.withLock { $0 } == 2)
        precondition(retry.requests.withLock { $0.last?.value(forHTTPHeaderField: "Authorization") } == "Bearer fixture-2")
        await expectFailure(.malformed) { _ = try await service(FixtureTransport([("invalid", 200)])).agents() }
        for url in ["https://127.0.0.1:8765", "http://localhost:8765", "http://example.test:8765", "http://127.0.0.1:8765/path"] {
            await expectFailure(.invalidURL) { _ = try OpenBotCredentials(url: url, token: "synthetic-secret") }
        }
        let unused = FixtureTransport([])
        await expectFailure(.oversized) {
            _ = try await service(unused).send(agent: "fixture-bot", text: String(repeating: "a", count: 32769))
        }
        precondition(unused.requests.withLock { $0.isEmpty })
        await expectFailure(.off) {
            _ = try await OpenBotService(transport: unused, credentials: { throw OpenBotFailure.off }).agents()
        }
        let late = FixtureTransport([(bots, 200)], delay: true)
        let module = OpenBotAgentsModule(service: service(late))
        module.start()
        while late.requests.withLock({ $0.isEmpty }) { await Task.yield() }
        module.stop()
        try await Task.sleep(for: .milliseconds(150))
        precondition(module.agents.isEmpty && module.pending.isEmpty && module.failure == nil)
        let pair = #"[{"id":"disabled","name":"Disabled"},{"id":"healthy","name":"Healthy"}]"#
        let mixed = FixtureTransport([(pair, 200), ("{}", 403), (#"{"prompts":[{}]}"#, 200)])
        var waitingCount: Int?
        let partial = OpenBotAgentsModule(service: service(mixed), report: { count, failure in
            waitingCount = count
            precondition(failure == nil)
        })
        partial.start()
        partial.start()
        await partial.waitUntilIdle()
        precondition(mixed.requests.withLock { $0.count } == 3)
        precondition(partial.agents.count == 2 && partial.failure == nil)
        precondition(partial.pending.values.filter(\.isWaiting).count == 1)
        precondition(partial.pendingFailures == ["disabled": .forbidden])
        mixed.responses.withLock { $0 = [(pair, 200), ("{}", 404), (#"{"approvals":[{}]}"#, 200)] }
        partial.refresh(reportResult: true)
        await partial.waitUntilIdle()
        precondition(waitingCount == 1 && partial.agents.count == 2)
        precondition(partial.pendingFailures == ["disabled": .missing])
        partial.stop()
        precondition(partial.pendingFailures.isEmpty)
        for cancelTask in [false, true] {
            let cancelled = FixtureTransport([], delay: cancelTask,
                error: URLError(cancelTask ? .timedOut : .cancelled))
            let request = Task { try await service(cancelled).agents() }
            if cancelTask {
                while cancelled.requests.withLock({ $0.isEmpty }) { await Task.yield() }
                request.cancel()
            }
            do {
                _ = try await request.value
                fatalError("Expected cancellation")
            } catch is CancellationError {} catch {
                fatalError("Cancellation became \(error)")
            }
        }
        let polling = FixtureTransport([]) { $0.url?.path.hasSuffix("/pending") == true ? (empty, 200) : (bots, 200) }
        var reports = 0
        let active = OpenBotAgentsModule(service: service(polling), pollInterval: .milliseconds(300), report: { count, failure in
            reports += 1
            precondition(count == 0 && failure == nil)
        })
        active.start()
        await active.waitUntilIdle()
        active.setActive(true)
        while polling.requests.withLock({ $0.count < 4 }) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(100))
        polling.requests.withLock { $0 = [] }
        active.refresh(reportResult: true)
        let deadline = ContinuousClock.now + .seconds(5)
        while polling.requests.withLock({ $0.count < 4 }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(100))
        precondition(polling.requests.withLock { $0.count } >= 4)
        precondition(active.agents.count == 1 && active.pending.count == 1 && reports == 1)
        active.stop()
        var availability = 0
        let gated = OpenBotAgentsModule(service: service(FixtureTransport([(bots, 200), (empty, 200)])),
                                        availabilityChanged: { availability += 1 })
        gated.start()
        gated.start()
        await gated.waitUntilIdle()
        gated.stop()
        precondition(availability == 2)
        precondition(!NotchcastFeature.openBotAgents.defaultEnabled)
        precondition(NotchcastFeature.openBotAgents.isWired && !NotchcastFeature.openBotAgents.needsIsland)
        let commands = [OpenBotAgentsModule.refreshCommand]
        precondition(commands.filter { $0.isEnabled() }.isEmpty)
        NotchcastPreferences.shared.enabled = true
        precondition(commands.filter { $0.isEnabled() }.count == 1)
        NotchcastPreferences.shared.enabled = false
        precondition(commands.filter { $0.isEnabled() }.isEmpty)
        let entries = OpenBotAgentsModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.openBotAgents] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === OpenBotAgentsModule.shared)
        print("PASS: registration entry")
        print("PASS: agents, pending questions/counts, receipt, all delivery statuses and malformed JSON")
        print("PASS: HTTP errors, single 401 credential retry, loopback, body limit, UUIDs, token redaction and stop")
        print("PASS: switch defaults off, independent of island; shipped command gate removes command when off")
        print("PASS: tolerant optional fields and non-string answers; wrong top-level types rejected")
        print("PASS: double start; isolated 403/404 pending failures, both agents listed, waiting count 1")
        print("PASS: active command refresh reports exactly once across two polling passes")
        print("PASS: URL cancellation and cancelled task transport failure surface as CancellationError")
        print("PASS: hook-shaped MainActor callbacks compile; lossy arrays retain valid neighbors in all five fields")
    }
}
