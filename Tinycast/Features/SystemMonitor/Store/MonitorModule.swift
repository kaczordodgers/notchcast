import AppKit
import Observation

@MainActor
final class MonitorModule: NotchcastModule {
    let store = MonitorStore()
    let fans = FanControl()
    let alerts: MonitorAlerts
    private let preferences: NotchcastPreferences
    private var running = false
    private var observationID: UUID?

    init(preferences: NotchcastPreferences, alertSink: @escaping (String) -> Void = { _ in }) {
        alerts = MonitorAlerts(sink: alertSink)
        self.preferences = preferences
    }

    func start() {
        guard !running else { return }
        running = true
        store.start()
        let identity = UUID()
        observationID = identity
        observe(identity)
        observeAlerts(identity)
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

    private func observeAlerts(_ identity: UUID) {
        guard running, observationID == identity else { return }
        withObservationTracking {
            alerts.evaluate(store.latest, rules: preferences.monitorAlertRules,
                            enabled: preferences.isOn(.systemMonitor) && preferences.isOn(.monitorAlerts),
                            demand: store.demand, at: Date())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAlerts(identity) }
        }
    }
}
