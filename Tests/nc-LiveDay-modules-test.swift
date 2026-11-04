// notchcast-sources: Tinycast/Features/LiveDay/DayWeatherModule.swift

// notchcast-sources: Tinycast/Features/LiveDay/Model/*.swift

// notchcast-sources: Tinycast/Features/LiveDay/Service/*.swift

// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift

import Foundation

@main
struct DayModulesTest {
    @MainActor static func main() {
        let suite = "day-modules-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DayWeatherStore(defaults: defaults, cacheURL: cache)
        let module = DayWeatherModule(store: store)
        module.start()
        precondition(!store.isRunning)
        module.setVisible(true)
        precondition(store.isRunning)
        module.stop()
        precondition(!store.isRunning)
        module.start()
        precondition(store.isRunning)
        module.setVisible(false)
        precondition(!store.isRunning)
        module.stop()
        module.setVisible(true)
        precondition(!store.isRunning)
        module.start()
        precondition(store.isRunning)
        module.stop()
        print("PASS weather module respects visibility, switch teardown and re-enable while visible")
    }
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = CommandIndexFixture()
}
@MainActor final class CommandIndexFixture {
    private(set) var refreshes = 0
    func refreshNotchcastCommands() { refreshes += 1 }
}
