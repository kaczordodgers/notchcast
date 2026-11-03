// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

@MainActor
final class TestModule: NotchcastModule {
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

/// Lets the controller's re-armed observation run, which happens on the main actor's next turn.
@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@main
@MainActor
struct NotchcastCoreTests {
    static func main() async {
        let suite = "notchcast-core-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let m0: Set = [
            "island", "islandExternalDisplays", "islandFullScreen", "islandHoverOpen",
            "islandStatusMessages", "islandLiveActivities", "launcherFromIsland"
        ]
        precondition(m0.isSubset(of: NotchcastFeature.allCases.map(\.rawValue)))
        precondition(NotchcastFeature.allCases.allSatisfy { preferences.isOn($0) })
        for feature in NotchcastFeature.allCases {
            preferences.set(feature, false)
            precondition(!NotchcastPreferences(suiteName: suite).isOn(feature))
            preferences.set(feature, true)
            precondition(NotchcastPreferences(suiteName: suite).isOn(feature))
        }
        let otherSuite = suite + ".other"
        defer { UserDefaults(suiteName: otherSuite)?.removePersistentDomain(forName: otherSuite) }
        preferences.set(.islandFullScreen, false)
        precondition(NotchcastPreferences(suiteName: otherSuite).isOn(.islandFullScreen))
        preferences.set(.islandFullScreen, true)

        let hover = TestModule()
        let ungated = TestModule()
        let controller = NotchcastModuleController(
            [
                .init(requires: [.island, .islandHoverOpen], module: hover),
                .init(requires: [.launcherFromIsland], module: ungated)
            ], preferences: preferences)
        controller.run()
        precondition(hover.starts == 1 && hover.stops == 0 && ungated.starts == 1)

        preferences.set(.islandHoverOpen, false)
        await settle()
        precondition(hover.starts == 1 && hover.stops == 1)
        preferences.set(.islandHoverOpen, true)
        await settle()
        precondition(hover.starts == 2)

        // A module not listing `.island` keeps running when the island turns off.
        preferences.set(.island, false)
        await settle()
        precondition(hover.stops == 2 && ungated.stops == 0)
        // A switch no entry requires never restarts anything.
        preferences.set(.islandStatusMessages, false)
        await settle()
        precondition(hover.starts == 2 && hover.stops == 2 && ungated.starts == 1)
        preferences.set(.island, true)
        await settle()
        precondition(hover.starts == 3 && ungated.starts == 1 && ungated.stops == 0)

        preferences.set(.launcherFromIsland, false)
        await settle()
        precondition(ungated.stops == 1 && hover.stops == 2)
        print("PASS: M0 switches default on, isolated persistence, requires-set gating through Observation")
    }
}
