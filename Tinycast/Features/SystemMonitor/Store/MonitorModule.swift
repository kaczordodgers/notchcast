import AppKit
import Observation

@MainActor
final class MonitorModule: NotchcastModule {
    let store: MonitorStore
    let fans: FanControl
    let alerts: MonitorAlerts
    private let preferences: NotchcastPreferences
    private var running = false
    private var observationID: UUID?
    private var alertDemand: MonitorStore.DemandToken?

    init(preferences: NotchcastPreferences, store: MonitorStore = MonitorStore(), alertSink: @escaping (String) -> Void = { _ in },
         fanFailure: @escaping () -> Void = {}) {
        self.store = store
        fans = FanControl(confirmed: { preferences.fanMode = $0.rawValue }, failed: fanFailure,
                          journalData: preferences.fanJournalData,
                          persist: { preferences.fanJournalData = $0 })
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
        alerts.resetBreaches()
        alertDemand?.cancel()
        alertDemand = nil
        store.stop()
        fans.restore(preservingPreference: true)
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
            let enabled = preferences.isOn(.systemMonitor) && preferences.isOn(.monitorAlerts)
            if enabled != (alertDemand != nil) {
                if enabled { alertDemand = store.beginDemand() } else {
                    alertDemand?.cancel()
                    alertDemand = nil
                }
            }
            alerts.evaluate(store.latest, rules: preferences.monitorAlertRules,
                            enabled: enabled,
                            demand: store.demand, at: Date())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAlerts(identity) }
        }
    }
}
