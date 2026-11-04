// notchcast-sources: Tinycast/Features/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorStore.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorAlerts.swift
import Foundation

@main
@MainActor
struct MonitorAlertsTests {
    static func main() {
        var calls: [String] = []
        let alerts = MonitorAlerts { calls.append($0) }
        let rules: [MonitorAlertRule.Metric: MonitorAlertRule] = [
            .cpu: .init(direction: .above, threshold: 90, recoverValue: 80,
                        sustainCount: 1, cooldown: 60)
        ]
        func evaluate(_ cpu: Double, _ time: Double, enabled: Bool = true, demand: Int = 1) {
            let snapshot = MonitorSnapshot(cpu: CPUReading(
                usage: .init(totalPercent: cpu, userPercent: cpu, systemPercent: 0),
                cores: [], loadAverage: nil))
            alerts.evaluate(snapshot, rules: rules, enabled: enabled, demand: demand,
                            at: Date(timeIntervalSince1970: time))
        }
        evaluate(90, 0)
        precondition(calls.isEmpty)
        evaluate(95, 1)
        precondition(calls.count == 1)
        evaluate(85, 70)
        evaluate(95, 71)
        precondition(calls.count == 1)
        evaluate(80, 72)
        evaluate(95, 73)
        precondition(calls.count == 2)
        evaluate(70, 74)
        evaluate(95, 75)
        precondition(calls.count == 2)
        evaluate(95, 134)
        precondition(calls.count == 3)
        evaluate(95, 200, enabled: false)
        evaluate(95, 300, demand: 0)
        precondition(calls.count == 3)
        print("PASS: threshold crossing, hysteresis, cooldown, disabled and no-demand gating")
    }
}
