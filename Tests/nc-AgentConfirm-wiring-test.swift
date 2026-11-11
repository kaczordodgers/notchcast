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
            timeout: .seconds(5)) { action, message, choices in
            precondition(message == "local-cli · \(action.id)")
            if action.danger == .dangerous {
                precondition(choices == [.allowOnce, .deny])
                precondition(!choices.contains(.alwaysAllow))
            }
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
        precondition(refused == nil)
        precondition(grants.grants.count == 1)
        let timeout = AgentConfirmationAuthorization(grants: grants, isEnabled: { true },
            timeout: .milliseconds(5)) { _, _, _ in
            try? await Task.sleep(for: .milliseconds(20))
            return 0
        }
        precondition(AgentRequestTiming.confirmationTimeout < AgentRequestTiming.serverTimeout)
        index.authorize = { action, parameters in
            await timeout.authorize(action, parameters: parameters)
        }
        try index.register(.init(action: dangerous, run: { _ in
            preconditionFailure("Timed-out action must not run")
        }))
        let expired = await index.handle(AgentRequest(verb: .run, id: dangerous.id))
        precondition(expired.code == .declined && expired.code.exit == 5)
        let detailed = AgentAction(id: "details", title: "Details", parameters: .init(properties: [
            "secret": .init(kind: .string, secret: true),
            "zebra": .init(kind: .string), "alpha": .init(kind: .number)
        ]))
        let message = detailed.confirmationMessage(parameters: .object([
            "zebra": .string(String(repeating: "x", count: 61)),
            "secret": .string("never-display-this"), "alpha": .number(2)
        ]))
        precondition(message == "local-cli · details\nalpha: 2\nsecret: •••\nzebra: "
            + String(repeating: "x", count: 60) + "…")
        precondition(!message.contains("never-display-this"))
        precondition(detailed.confirmationMessage(parameters: .object([:])) == "local-cli · details")
        var events: [String] = []
        var upstream: CheckedContinuation<Void, Never>?
        var agentChoice: CheckedContinuation<Void, Never>?
        let queued = AgentConfirmationAuthorization(grants: grants, isEnabled: { true }) { action, _, choices in
            events.append(action.id)
            if action.id == "volume" {
                precondition(choices == [.allowOnce, .deny])
            } else {
                precondition(choices == [.allowOnce, .alwaysAllow, .deny])
            }
            if action.id == "restart" { await withCheckedContinuation { agentChoice = $0 } }
            return 0
        }
        let queueIndex = AgentActionIndex()
        queueIndex.authorize = { action, parameters in await queued.authorize(action, parameters: parameters) }
        try queueIndex.register(.init(action: .init(id: "restart", title: "Restart"), run: { _ in
            events.append("upstream confirm")
            await withCheckedContinuation { upstream = $0 }
            events.append("restart ran")
            return .null
        }))
        let volume = AgentAction(id: "volume", title: "Set Volume", parameters: .init(
            properties: ["level": .init(kind: .number)], required: ["level"]))
        try grants.allow(agentID: "local-cli", actionID: volume.id, danger: .consent, now: Date())
        try queueIndex.register(.init(action: volume, run: { _ in .null }))
        queueIndex.start()
        let restart = Task { await queueIndex.handle(.init(verb: .run, id: "restart")) }
        while agentChoice == nil { await Task.yield() }
        let setVolume = Task { await queueIndex.handle(.init(verb: .run, id: "volume",
            parameters: .object(["level": .number(0)]))) }
        try? await Task.sleep(for: .milliseconds(20))
        precondition(events == ["restart"])
        agentChoice?.resume()
        while upstream == nil { await Task.yield() }
        precondition(events == ["restart", "upstream confirm"])
        upstream?.resume()
        let restartReply = await restart.value
        let volumeReply = await setVolume.value
        precondition(restartReply.code == .ok && volumeReply.code == .ok)
        precondition(events == ["restart", "upstream confirm", "restart ran", "volume"])
        queued.stop()
        try? await Task.sleep(for: .milliseconds(30))
        authorization.stop()
        timeout.stop()
        var held: CheckedContinuation<Int, Never>?
        var dismissed = false
        let expiring = AgentConfirmationAuthorization(grants: grants, isEnabled: { true },
            timeout: .milliseconds(50)) { _, _, _ in
            let result = await withCheckedContinuation { held = $0 }
            dismissed = true
            return result
        }
        let expirations = (0..<20).map { _ in
            Task { await expiring.authorize(dangerous, parameters: .null) }
        }
        for task in expirations {
            let result = await task.value
            precondition(result == nil)
        }
        precondition(held != nil)
        held?.resume(returning: 1)
        while !dismissed { await Task.yield() }
        var tables: [String] = []
        for child in Mirror(reflecting: expiring).children {
            let table = Mirror(reflecting: child.value)
            guard table.displayStyle == .dictionary, let label = child.label else { continue }
            tables.append(label)
            precondition(table.children.isEmpty, "Expired request bookkeeping retained: \(label)")
        }
        precondition(tables.count == 3, "Expected 3 per-request dictionaries, found \(tables)")
        held = nil
        let fresh = Task { await expiring.authorize(dangerous, parameters: .null) }
        for _ in 0..<10_000 where held == nil { await Task.yield() }
        precondition(held != nil, "A fresh request after 20 expirations never reached the presenter")
        held?.resume(returning: 0)
        let allowed = await fresh.value
        precondition(allowed != nil, "The presenter's Allow once was not honoured")
        expiring.stop()
        print("PASS: 20 expired requests leave the authorization's own dictionaries empty: \(tables.joined(separator: ", "))")
        print("PASS: after 20 expired requests a fresh one reaches the presenter and its answer is honoured")
        print("PASS: queue held through upstream confirm; parameterized stored grants prompt; parameterless Always allow")
    }
}
