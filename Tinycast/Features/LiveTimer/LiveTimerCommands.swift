import Foundation

extension LiveTimerModule {
    nonisolated static let startCommand = NotchcastCommand(
        slug: "start-timer", name: String(localized: "Start Timer", table: "Notchcast"), sfSymbol: "timer", feature: .liveTimers,
        isEnabled: { NotchcastPreferences.shared.isOn(.island) && NotchcastPreferences.shared.isOn(.liveTimers) },
        run: { LiveTimerModule.shared.store.start() })

    nonisolated static let stopCommand = NotchcastCommand(
        slug: "stop-timer", name: String(localized: "Stop Timer", table: "Notchcast"), sfSymbol: "stop.circle", feature: .liveTimers,
        isEnabled: { startCommand.isEnabled() },
        run: {
            let store = LiveTimerModule.shared.store
            store.stopNext()
        })
}
