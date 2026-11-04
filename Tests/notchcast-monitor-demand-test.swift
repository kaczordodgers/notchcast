// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorModule.swift
import Foundation
import Observation

@MainActor protocol NotchcastModule { func start(); func stop() }
enum Feature { case systemMonitor
    case monitorAlerts
    case fanControl
}
@MainActor @Observable final class NotchcastPreferences {
    var enabled = true
    var fanMode = "auto"
    var monitorAlertRules: [String: Int] = [:]
    func isOn(_ feature: Feature) -> Bool { feature == .fanControl ? false : enabled }
}
@MainActor final class FanControl {
    enum Mode: String { case auto }
    func set(_ mode: Mode) {}
    func restore() {}
}
@MainActor @Observable final class MonitorStore {
    var demand = 0
    var alertDemand = false
    var latest = 0
    func start() {}
    func stop() {}
    func acquire() { demand += 1 }
    func release() { demand -= 1 }
    func setAlertDemand(_ value: Bool) { alertDemand = value }
}
@MainActor final class MonitorAlerts {
    init(sink: @escaping (String) -> Void) {}
    func resetBreaches() {}
    func evaluate(_ sample: Int, rules: [String: Int], enabled: Bool, demand: Int, at: Date) {}
}
@main @MainActor struct DemandTests {
    static func main() async {
        let preferences = NotchcastPreferences()
        let store = MonitorStore()
        let module = MonitorModule(preferences: preferences, store: store, alertSink: { _ in })
        module.start()
        precondition(store.demand == 0 && store.alertDemand)
        store.acquire()
        precondition(store.demand == 1 && store.alertDemand)
        store.release()
        precondition(store.demand == 0 && store.alertDemand)
        preferences.enabled = false
        for _ in 0..<200 { await Task.yield() }
        precondition(!store.alertDemand && store.demand == 0)
        module.stop()
        print("PASS: alerts-only demand, page upgrade/downgrade, disable and stop")
    }
}
