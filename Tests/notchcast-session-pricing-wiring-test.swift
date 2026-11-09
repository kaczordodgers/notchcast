// notchcast-sources: Tinycast/Features/AgentSessions/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/Pricing/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/AgentSessionsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import Foundation
import Observation
import Synchronization

@main
struct SessionPricingWiringTests {
    @MainActor static func main() async throws {
        guard let resolved = realpath(NSTemporaryDirectory(), nil) else { fatalError("Fixture root") }
        let root = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent(UUID().uuidString)
        free(resolved)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = """
        {"type":"assistant","sessionId":"synthetic","timestamp":"2026-01-02T03:04:05Z",
        "message":{"id":"one","model":"gpt-4.1","usage":{"input_tokens":1000000,"output_tokens":1000000}}}
        """.replacingOccurrences(of: "\n", with: "") + "\n"
        try Data(fixture.utf8).write(to: root.appendingPathComponent("session.jsonl"))
        let suite = "test.session-pricing." + UUID().uuidString
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        precondition(!preferences.isOn(.agentSessions) && !preferences.isOn(.agentPricing))
        preferences.set(.agentSessions, true)
        preferences.set(.agentPricing, true)
        let privateConfig = root.appendingPathComponent("private.env")
        try Data("NOTCHCAST_AGENT_SESSIONS_EXCLUDE=private-fixture\n".utf8).write(to: privateConfig)
        let accesses = Mutex<[URL]>([])
        let pricingRuns = Mutex(0)
        let excluded = root.appendingPathComponent("private-fixture")
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        let module = AgentSessionsModule(roots: [.init(provider: .claude, url: root),
                                                .init(provider: .claude, url: excluded)],
            preferences: preferences, index: AgentSessionIndex { url in
                accesses.withLock { $0.append(url) }
            }, privateConfigURL: privateConfig, price: { sessions, calendar in
                pricingRuns.withLock { $0 += 1 }
                return AgentSessionPricing.report(sessions, calendar: calendar)
            })
        let controller = NotchcastModuleController([
            .init(requires: [.agentSessions], module: module)
        ], preferences: preferences)
        controller.run()
        module.refresh()
        for _ in 0..<200 {
            if module.pricingReport?.total.costUSD == 10 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(module.pricingReport?.total.costUSD == 10,
                     "snapshot=\(module.snapshot) report=\(String(describing: module.pricingReport))")
        precondition(module.pricingReport?.days.count == 1)
        let runs = pricingRuns.withLock { $0 }
        let snapshotChanges = Mutex(0)
        withObservationTracking {
            _ = module.snapshot
        } onChange: {
            snapshotChanges.withLock { $0 += 1 }
        }
        for _ in 0..<5 {
            module.refresh()
            await module.waitUntilIdle()
        }
        precondition(pricingRuns.withLock { $0 } == runs, "Identical scans must not run pricing")
        precondition(snapshotChanges.withLock { $0 } == 0, "Identical scans must not publish snapshots")
        let changed = fixture.replacingOccurrences(of: "1000000", with: "2000000")
        try Data(changed.utf8).write(to: root.appendingPathComponent("session.jsonl"))
        module.refresh()
        await module.waitUntilIdle()
        precondition(pricingRuns.withLock { $0 } == runs + 1 && module.pricingReport?.total.costUSD == 20)
        precondition(AgentSessionsModule.pollInterval == .seconds(30), "Bound recursive polling")
        precondition(accesses.withLock { $0.allSatisfy { !$0.pathComponents.contains("private-fixture") } })
        preferences.set(.agentPricing, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(module.pricingReport == nil && module.snapshot.sessions.count == 1)
        preferences.set(.agentPricing, true)
        for _ in 0..<20 { await Task.yield() }
        precondition(pricingRuns.withLock { $0 } == runs + 2, "Switch change prices exactly once")
        module.setDemand(true)
        try await Task.sleep(for: .milliseconds(500))
        let pollAccesses = accesses.withLock { $0.count }
        try await Task.sleep(for: .milliseconds(2200))
        precondition(accesses.withLock { $0.count } == pollAccesses,
                     "Demand must not recursively walk again after only two seconds")
        module.setDemand(false)
        module.stop()
        let excludedFixture = fixture.replacingOccurrences(of: "synthetic", with: "excluded-session")
        try Data(excludedFixture.utf8).write(to: excluded.appendingPathComponent("session.jsonl"))
        module.start()
        module.refresh()
        await module.waitUntilIdle()
        precondition(module.snapshot.sessions.count == 1, "Restart preserves configured exclusions")
        try FileManager.default.removeItem(at: privateConfig)
        module.refresh()
        await module.waitUntilIdle()
        precondition(module.snapshot.sessions.count == 2, "Missing config excludes nothing")
        try Data("NOTCHCAST_AGENT_SESSIONS_EXCLUDE=private-fixture\n".utf8).write(to: privateConfig)
        module.refresh()
        await module.waitUntilIdle()
        precondition(module.snapshot.sessions.count == 1, "New exclusions evict previously indexed sessions")
        let beforeInvalidConfig = accesses.withLock { $0.count }
        try Data([0xff]).write(to: privateConfig)
        module.refresh()
        await module.waitUntilIdle()
        precondition(accesses.withLock { $0.count } == beforeInvalidConfig, "Invalid config prevents scanning")
        module.stop()
        print("PASS: synthetic pricing, switches, daily totals, fixture config, missing config and excluded root access")
    }
}
