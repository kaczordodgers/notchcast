import Foundation

@MainActor
final class TestModule: NotchcastModule {
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

@main
@MainActor
struct NotchcastCoreTests {
    static func main() {
        let suite = "notchcast-core-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(NotchcastFeature.allCases.count == 7)
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
        let module = TestModule()
        let controller = NotchcastModuleController([.init(feature: .islandHoverOpen, module: module)])
        preferences.onChange = { _ in controller.update(preferences) }
        controller.update(preferences)
        precondition(module.starts == 1 && module.stops == 0)
        preferences.set(.islandHoverOpen, false)
        preferences.set(.islandHoverOpen, false)
        precondition(module.starts == 1 && module.stops == 1)
        preferences.set(.islandHoverOpen, true)
        precondition(module.starts == 2)
        preferences.set(.island, false)
        precondition(module.stops == 2)
        preferences.set(.islandStatusMessages, false)
        precondition(module.starts == 2 && module.stops == 2)
        preferences.set(.island, true)
        precondition(module.starts == 3)
        print("PASS: seven defaults, isolated persistence, synchronous module start/stop and master switch")
    }
}
