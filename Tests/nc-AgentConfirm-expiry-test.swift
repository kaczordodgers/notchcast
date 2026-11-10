// notchcast-sources: Tinycast/Features/AgentConfirm/Model/*.swift Tinycast/Features/AgentConfirm/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/AgentConsentPolicy.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/AgentGrantStore.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/AgentActionIndex.swift
import Foundation

@MainActor
final class Screen {
    var open: CheckedContinuation<Int, Never>?

    func close(_ index: Int) {
        open?.resume(returning: index)
        open = nil
    }
}

// An unanswered confirmation closes at its deadline and the next request is shown.
@main
@MainActor
struct ConfirmationExpiryTests {
    static func main() async throws {
        let suite = "test.confirmation.expiry." + UUID().uuidString
        let grants = try AgentGrantStore(bundleIdentifier: suite)
        defer {
            UserDefaults(suiteName: suite + ".notchcast.agent-consent")?
                .removePersistentDomain(forName: suite + ".notchcast.agent-consent")
        }
        var shown: [String] = []
        let screen = Screen()
        let authorization = AgentConfirmationAuthorization(grants: grants, isEnabled: { true },
            timeout: .milliseconds(100)) { action, _, choices in
            shown.append(action.id)
            return await withTaskCancellationHandler {
                await withCheckedContinuation { screen.open = $0 }
            } onCancel: {
                Task { @MainActor in screen.close(choices.count - 1) }
            }
        }
        let index = AgentActionIndex()
        var runs: [String] = []
        for id in ["first", "second"] {
            try index.register(.init(action: .init(id: id, title: id), run: { _ in
                runs.append(id)
                return .null
            }))
        }
        index.authorize = { action, parameters in await authorization.authorize(action, parameters: parameters) }
        index.start()
        let first = await index.handle(AgentRequest(verb: .run, id: "first"))
        precondition(first.code == .declined && runs.isEmpty, "expired request must be declined")
        for _ in 0..<100 where screen.open != nil { try await Task.sleep(for: .milliseconds(10)) }
        precondition(screen.open == nil, "dialog of an expired request stayed open")
        let second = Task { await index.handle(AgentRequest(verb: .run, id: "second")) }
        for _ in 0..<100 where screen.open == nil { try await Task.sleep(for: .milliseconds(10)) }
        precondition(shown == ["first", "second"], "request after an expiry was not shown: \(shown)")
        screen.close(0)
        let reply = await second.value
        precondition(reply.code == .ok && runs == ["second"], "Allow once on the next dialog did not run it")
        authorization.stop()
        print("PASS: expired confirmation closes its dialog and the next request is shown and runs")
    }
}
