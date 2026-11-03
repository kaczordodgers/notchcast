import AppKit
import Observation

@MainActor
final class MonitorModule: NotchcastModule {
    let store = MonitorStore()
    let fans = FanControl()
    private let preferences: NotchcastPreferences
    private var running = false
    private var termination: NotificationToken?

    init(preferences: NotchcastPreferences) {
        self.preferences = preferences
        termination = NotificationToken(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fans.restore() }
        }, center: .default)
    }

    func start() {
        running = true
        store.start()
        observe()
    }

    func stop() {
        running = false
        store.stop()
        fans.restore()
    }

    private func observe() {
        guard running else { return }
        withObservationTracking {
            fans.set(preferences.isOn(.fanControl) ? FanControl.Mode(rawValue: preferences.fanMode) ?? .auto : .auto)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}
