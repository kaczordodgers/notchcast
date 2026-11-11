// notchcast-sources: Tinycast/Features/AgentConfirm/Model/*.swift Tinycast/Features/AgentConfirm/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/AgentConsentPolicy.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/AgentGrantStore.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
import Foundation

@MainActor
final class FakeConfirmationTransport: AgentConfirmationTransport, AgentConfirmationActions {
    var replies: [AgentConfirmationEngine.Reply] = []
    func reply(_ reply: AgentConfirmationEngine.Reply) { replies.append(reply) }
    func confirmationDanger(agentID: String, actionID: String) -> AgentConsentPolicy.Danger? {
        actionID == "unknown" ? nil : actionID == "kill" ? .dangerous : .consent
    }
    func request(_ request: AgentConfirmationEngine.Request, to coordinator: AgentConfirmationCoordinator,
                 now: Date) {
        coordinator.receive(request, now: now)
    }
}

@main
struct AgentConfirmationTests {
    @MainActor
    static func main() throws {
        let now = Date(timeIntervalSince1970: 100)
        let suite = "test.agent-confirm." + UUID().uuidString
        let grants = try AgentGrantStore(bundleIdentifier: suite, key: "agentActionGrants")
        defer {
            UserDefaults(suiteName: suite + ".notchcast.agent-consent")?
                .removePersistentDomain(forName: suite + ".notchcast.agent-consent")
        }
        let transport = FakeConfirmationTransport()
        var enabled = true
        let coordinator = AgentConfirmationCoordinator(transport: transport, actions: transport,
                                                      grants: grants, isEnabled: { enabled })
        func request(_ action: String = "write", agent: String = "agent") -> AgentConfirmationEngine.Request {
            .init(id: UUID(), agentID: agent, client: "client", actionID: action,
                  parameters: ["approve": "true"], deadline: now.addingTimeInterval(10))
        }
        let first = request(), second = request()
        transport.request(first, to: coordinator, now: now)
        transport.request(second, to: coordinator, now: now)
        assert(transport.replies.isEmpty)
        try coordinator.choose(id: second.id, choice: .allowOnce, now: now)
        assert(transport.replies.isEmpty)
        try coordinator.choose(id: first.id, choice: .allowOnce, now: now)
        assert(transport.replies.last?.verdict == .allowOnce)
        try coordinator.choose(id: second.id, choice: .deny, now: now)
        assert(transport.replies.last?.verdict == .deny)
        let persistent = request()
        coordinator.receive(persistent, now: now)
        try coordinator.choose(id: persistent.id, choice: .alwaysAllow, now: now)
        assert(grants.grants.count == 1)
        let dangerous = request("kill")
        coordinator.receive(dangerous, now: now)
        try coordinator.choose(id: dangerous.id, choice: .alwaysAllow, now: now)
        assert(transport.replies.last?.verdict == .deny)
        let expired = request()
        coordinator.receive(expired, now: now)
        coordinator.tick(now: now.addingTimeInterval(10))
        try coordinator.choose(id: expired.id, choice: .allowOnce, now: now.addingTimeInterval(10))
        assert(transport.replies.last == .init(id: expired.id, verdict: .deny))
        let duplicate = request()
        coordinator.receive(duplicate, now: now)
        coordinator.receive(duplicate, now: now)
        try coordinator.choose(id: duplicate.id, choice: .allowOnce, now: now)
        assert(transport.replies.last == .init(id: duplicate.id, verdict: .deny))
        coordinator.receive(request(agent: " "), now: now)
        assert(transport.replies.last?.verdict == .deny)
        coordinator.receive(request("unknown"), now: now)
        assert(transport.replies.last?.verdict == .deny)
        let pendingOnDisable = request()
        coordinator.receive(pendingOnDisable, now: now)
        enabled = false
        coordinator.tick(now: now)
        assert(transport.replies.last == .init(id: pendingOnDisable.id, verdict: .deny))
        assert(coordinator.engine.queue.isEmpty)
        coordinator.receive(request(), now: now)
        assert(transport.replies.last?.verdict == .deny)
        enabled = true
        let pendingOnStop = request()
        coordinator.receive(pendingOnStop, now: now)
        coordinator.stop()
        assert(transport.replies.last == .init(id: pendingOnStop.id, verdict: .deny))
        assert(coordinator.engine.queue.isEmpty)
        print("Agent confirmation: queue, local decisions, grants, timeout, duplicate, malformed, disable passed")
    }
}
