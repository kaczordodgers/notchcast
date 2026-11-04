import AppKit
import Observation

@MainActor
final class MonitorModule: NotchcastModule {
    let store = MonitorStore()
    let fans = FanControl()
    private let preferences: NotchcastPreferences
    private var running = false
    private var observationID: UUID?

    init(preferences: NotchcastPreferences) {
        self.preferences = preferences
    }

    func start() {
        guard !running else { return }
        running = true
        store.start()
        let identity = UUID()
        observationID = identity
        observe(identity)
    }

    func stop() {
        running = false
        observationID = nil
        store.stop()
        fans.restore()
    }

    private func observe(_ identity: UUID) {
        guard running, observationID == identity else { return }
        withObservationTracking {
            fans.set(preferences.isOn(.fanControl) ? FanControl.Mode(rawValue: preferences.fanMode) ?? .auto : .auto)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe(identity) }
        }
    }
}
