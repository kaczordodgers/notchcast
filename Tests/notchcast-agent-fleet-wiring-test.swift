// notchcast-sources: Tinycast/Features/AgentFleet/T3Threads.swift
// notchcast-sources: Tinycast/Features/AgentFleet/T3Threads/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/T3Threads/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/T3Threads/T3ThreadsModule.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Waiting/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetSnapshot.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetThreadSource.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetModel.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetModule.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Island/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Island/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentFleet/BotHost/BotHostModule.swift
// notchcast-sources: Tinycast/Features/AgentFleet/BotHostIslandSource.swift
// notchcast-sources: Tinycast/Features/AgentFleet/AgentFleetWiring.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation

@MainActor enum NotchcastCore {}

@main @MainActor struct WiringTest {
    static func settle() async {
        for _ in 0..<100 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(100))
    }

    static func main() async {
        let suite = "fleet-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let threads = T3ThreadsModule(source: .init(runner: {
            Data(#"[{"threadId":"fixture","title":"Fixture","status":"waiting_for_approval"}]"#.utf8)
        }))
        let fleet = FleetModule()
        let island = AgentIslandModule()
        let bots = BotHostModule()
        let wiring = AgentFleetWiring(threads: threads, fleet: fleet, island: island, bots: bots,
            preferences: preferences, post: { _ in })
        let controller = NotchcastModuleController([
            .init(requires: [.t3Threads], module: threads),
            .init(requires: [.fleetPanel], module: fleet),
            .init(requires: [.agentIsland], module: island),
            .init(requires: [], module: wiring)
        ], preferences: preferences)
        for feature in [NotchcastFeature.t3Threads, .waitingAlerts, .fleetPanel, .agentIsland, .botHost] {
            precondition(!preferences.isOn(feature))
            preferences.set(feature, true)
        }
        controller.run()
        await settle()
        await wiring.alerts.settle()
        precondition(wiring.alerts.count == 1)
        precondition(fleet.model?.rows.count == 1)
        precondition(island.state.presentations["t3"]?.mode == .approval)
        preferences.set(.waitingAlerts, false)
        await settle()
        precondition(wiring.alerts.count == 0)
        preferences.set(.fleetPanel, false)
        await settle()
        precondition(fleet.model?.rows.isEmpty == true)
        preferences.set(.agentIsland, false)
        await settle()
        precondition(island.state.presentations.isEmpty)
        preferences.set(.t3Threads, false)
        await settle()
        precondition(!threads.isRunning && threads.threads.isEmpty)
        wiring.stop()
        print("PASS: fake snapshot fanout and independent switch teardown")
    }
}
