// notchcast-sources: Tinycast/Features/AgentSessions/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/Pricing/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/AgentSessionsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import Foundation
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
        let accesses = Mutex<[URL]>([])
        let excluded = root.appendingPathComponent("agent-2784f2ac")
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        let module = AgentSessionsModule(roots: [.init(provider: .claude, url: root),
                                                .init(provider: .claude, url: excluded)],
            preferences: preferences, index: AgentSessionIndex { url in
                accesses.withLock { $0.append(url) }
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
        precondition(accesses.withLock { $0.allSatisfy { !$0.pathComponents.contains("agent-2784f2ac") } })
        preferences.set(.agentPricing, false)
        for _ in 0..<20 { await Task.yield() }
        precondition(module.pricingReport == nil && module.snapshot.sessions.count == 1)
        module.stop()
        print("PASS: synthetic session pricing, switches, daily totals and excluded root access")
    }
}
