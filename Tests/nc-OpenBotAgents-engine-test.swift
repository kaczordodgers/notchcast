// notchcast-sources: Tinycast/Features/OpenBotAgents/Model/*.swift
// notchcast-sources: Tinycast/Features/OpenBotAgents/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/OpenBotAgents/OpenBotAgentsModule+Command.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
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
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor
enum NotchcastCore {
    static let openBotAgents = OpenBotAgentsModule()
}

@MainActor
final class AppCore {
    enum Tone { case neutral }
    static let shared = AppCore()
    func showMessage(_ text: String, tone: Tone) {}
}

final class FixtureTransport: OpenBotTransport {
    let responses: Mutex<[(String, Int)]>
    let requests = Mutex<[URLRequest]>([])
    let delay: Bool

    init(_ responses: [(String, Int)], delay: Bool = false) {
        self.responses = Mutex(responses)
        self.delay = delay
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.withLock { $0.append(request) }
        if delay { try? await Task.sleep(for: .milliseconds(100)) }
        let response = responses.withLock { $0.removeFirst() }
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
        for status in ["queued", "pending", "running", "completed", "failed", "interrupted", "cancelled", "future"] {
            let fixture = "{\"id\":\"fixture-delivery\",\"status\":\"\(status)\",\"answer\":null}"
            let delivery = try await service(FixtureTransport([(fixture, 200)]))
                .delivery(agent: "fixture-bot", id: "fixture-delivery")
            precondition(delivery.status == OpenBotDelivery.Status(rawValue: status) ?? .unknown)
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
        precondition(!NotchcastFeature.openBotAgents.defaultEnabled)
        precondition(NotchcastFeature.openBotAgents.isWired && !NotchcastFeature.openBotAgents.needsIsland)
        let commands = [OpenBotAgentsModule.refreshCommand]
        precondition(commands.filter { $0.isEnabled() }.isEmpty)
        NotchcastPreferences.shared.enabled = true
        precondition(commands.filter { $0.isEnabled() }.count == 1)
        NotchcastPreferences.shared.enabled = false
        precondition(commands.filter { $0.isEnabled() }.isEmpty)
        print("PASS: agents, pending questions/counts, receipt, all delivery statuses and malformed JSON")
        print("PASS: HTTP errors, single 401 credential retry, loopback, body limit, UUIDs, token redaction and stop")
        print("PASS: switch defaults off, independent of island; shipped command gate removes command when off")
        print("PASS: tolerant optional fields and non-string answers; wrong top-level types rejected")
        print("PASS: double start; isolated 403/404 pending failures, both agents listed, waiting count 1")
    }
}
