import Foundation

extension LiveTimerModule {
    nonisolated static let startCommand = NotchcastCommand(
        slug: "start-timer", name: String(localized: "Start Timer"), sfSymbol: "timer",
        isEnabled: { NotchcastPreferences.shared.isOn(.island) && NotchcastPreferences.shared.isOn(.liveTimers) },
        run: { NotchcastCore.timers.store.start() })

    nonisolated static let stopCommand = NotchcastCommand(
        slug: "stop-timer", name: String(localized: "Stop Timer"), sfSymbol: "stop.circle",
        isEnabled: { startCommand.isEnabled() },
        run: {
            let store = NotchcastCore.timers.store
            if let timer = store.ringing.first ?? store.nextTimer { store.cancel(timer.id) }
        })
}
