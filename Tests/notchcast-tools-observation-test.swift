// notchcast-sources: Tinycast/Features/Notchcast/Tools/NotchcastToolsCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

@main @MainActor struct ToolsObservationTest {
    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    static func main() async {
        let suite = "tools-observation-\(UUID())"
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        var refreshes = 0
        let controller = NotchcastToolsCommands(preferences: preferences, selection: { [] }, post: { _ in },
                                                refresh: { refreshes += 1 }) { _, _, _ in }
        func refreshesAfterChange() async -> Int {
            await settle()
            refreshes = 0
            preferences.set(.mediaTools, !preferences.isOn(.mediaTools))
            await settle()
            return refreshes
        }
        controller.start()
        let single = await refreshesAfterChange()
        precondition(single > 0, "A switch change must refresh the commands")
        controller.stop()
        controller.start()
        controller.stop()
        controller.start()
        let restarted = await refreshesAfterChange()
        precondition(restarted == single, "Stop must end its chains: \(single) refreshes expected, got \(restarted)")
        controller.start()
        let doubleStart = await refreshesAfterChange()
        precondition(doubleStart == single, "A second start must not add chains, got \(doubleStart)")
        controller.stop()
        let stopped = await refreshesAfterChange()
        precondition(stopped == 0, "A stopped controller must not re-run, got \(stopped)")
        print("PASS: one switch observation chain per feature across stop/start")
    }
}
