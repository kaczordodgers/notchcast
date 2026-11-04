// notchcast-sources: Tinycast/Features/LiveTimer/LiveTimerModule.swift

// notchcast-sources: Tinycast/Features/LiveTimer/Model/*.swift

// notchcast-sources: Tinycast/Features/LiveTimer/Service/*.swift

// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift

import Foundation

@main
struct TimerModuleTest {
    @MainActor static func main() {
        let suite = "timer-module-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var instant = Date(timeIntervalSince1970: 1_000)
        var sounds = 0
        let store = LiveTimerStore(defaults: defaults, clock: { instant }, playSound: { sounds += 1 },
                                   stopSound: {}, active: false)
        let module = LiveTimerModule(store: store)
        let timer = store.start(1)!
        instant = instant.addingTimeInterval(2)
        precondition(sounds == 0)
        module.start()
        precondition(store.ringing.first?.id == timer && sounds == 1)
        module.stop()
        instant = instant.addingTimeInterval(3)
        store.playSoundWhenTimeIsUp = false
        store.playSoundWhenTimeIsUp = true
        store.refresh()
        precondition(sounds == 1)
        module.start()
        precondition(sounds == 2)
        module.stop()
        print("PASS timer module owns ringing, switch teardown and resuming persisted timers")
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
