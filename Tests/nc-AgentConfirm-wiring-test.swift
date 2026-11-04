// notchcast-sources: Tinycast/Features/AgentConfirm/Model/*.swift Tinycast/Features/AgentConfirm/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/AgentConsentPolicy.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/AgentGrantStore.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/AgentActionIndex.swift
import Foundation

@main
@MainActor
struct ConfirmationWiringTests {
    static func main() async throws {
        let suite = "test.confirmation." + UUID().uuidString
        let grants = try AgentGrantStore(bundleIdentifier: suite)
        defer {
            UserDefaults(suiteName: suite + ".notchcast.agent-consent")?
                .removePersistentDomain(forName: suite + ".notchcast.agent-consent")
        }
        var enabled = true
        var prompts = 0
        var active = 0
        var maximum = 0
        var answer = 0
        let authorization = AgentConfirmationAuthorization(grants: grants, isEnabled: { enabled },
            timeout: .seconds(5)) { _, choices in
            prompts += 1
            active += 1
            maximum = max(maximum, active)
            try? await Task.sleep(for: .milliseconds(10))
            active -= 1
            return min(answer, choices.count - 1)
        }
        let index = AgentActionIndex()
        var runs = 0
        try index.register(.init(action: .init(id: "write", title: "Write"), run: { _ in
            runs += 1
            return .null
        }))
        index.authorize = { action, parameters in
            await authorization.authorize(action, parameters: parameters)
        }
        index.start()
        let request = AgentRequest(verb: .run, id: "write")
        let first = await index.handle(request)
        precondition(first.code == .ok && runs == 1 && prompts == 1)
        answer = 2
        let denied = await index.handle(request)
        precondition(denied.code == .declined && denied.code.exit == 5 && runs == 1)
        answer = 0
        async let a = index.handle(request)
        async let b = index.handle(request)
        let pair = await (a, b)
        precondition(pair.0.code == .ok && pair.1.code == .ok && maximum == 1 && runs == 3)
        enabled = false
        let count = prompts
        let off = await index.handle(request)
        precondition(off.code == .declined && prompts == count)
        enabled = true
        answer = 1
        let always = await index.handle(request)
        precondition(always.code == .ok && grants.grants.count == 1)
        let before = prompts
        _ = await index.handle(request)
        precondition(prompts == before)
        let dangerous = AgentAction(id: "kill", title: "Kill", danger: .dangerous)
        let refused = await authorization.authorize(dangerous, parameters: .null)
        precondition(!refused)
        precondition(grants.grants.count == 1)
        let timeout = AgentConfirmationAuthorization(grants: grants, isEnabled: { true },
            timeout: .milliseconds(5)) { _, _ in
            try? await Task.sleep(for: .milliseconds(20))
            return 0
        }
        let expired = await timeout.authorize(dangerous, parameters: .null)
        precondition(!expired)
        try? await Task.sleep(for: .milliseconds(30))
        authorization.stop()
        timeout.stop()
        print("PASS: switch, single execution, persistent consent grant, dangerous refusal, exit 5, serialized queue, timeout")
    }
}
