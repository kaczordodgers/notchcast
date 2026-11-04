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
        evaluate(70, 135)
        evaluate(95, 136, demand: 0)
        evaluate(95, 137)
        precondition(calls.count == 3)
        evaluate(95, 1035)
        precondition(calls.count == 4)
        evaluate(95, 200, enabled: false)
        evaluate(95, 300, demand: 0)
        precondition(calls.count == 4)

        var sustainedCalls = 0
        let sustained = MonitorAlerts { _ in sustainedCalls += 1 }
        let sustainedRules: [MonitorAlertRule.Metric: MonitorAlertRule] = [
            .cpu: .init(direction: .above, threshold: 90, recoverValue: 80)
        ]
        func highSample() -> MonitorSnapshot {
            MonitorSnapshot(cpu: CPUReading(
                usage: .init(totalPercent: 95, userPercent: 95, systemPercent: 0),
                cores: [], loadAverage: nil))
        }
        func check(_ sample: MonitorSnapshot, enabled: Bool = true, demand: Int = 1,
                   time: Double = 0) {
            sustained.evaluate(sample, rules: sustainedRules, enabled: enabled, demand: demand,
                               at: Date(timeIntervalSince1970: time))
        }
        let first = highSample()
        check(first)
        check(first)
        check(first)
        precondition(sustainedCalls == 0, "preference observations cannot recount a sample")
        let second = highSample()
        check(second)
        check(second, enabled: false, demand: 0)
        check(second, time: 3600)
        precondition(sustainedCalls == 0, "resuming cannot evaluate the retained snapshot")
        check(highSample(), time: 3602)
        check(highSample(), time: 3604)
        precondition(sustainedCalls == 0, "zero demand clears the previous breach streak")
        check(highSample(), time: 3606)
        precondition(sustainedCalls == 1)

        var streakCalls = 0
        let streak = MonitorAlerts { _ in streakCalls += 1 }
        func streakCheck(enabled: Bool = true) {
            streak.evaluate(highSample(), rules: sustainedRules, enabled: enabled, demand: 1,
                            at: Date(timeIntervalSince1970: 0))
        }
        streakCheck()
        streakCheck()
        streakCheck(enabled: false)
        streakCheck()
        streakCheck()
        precondition(streakCalls == 0, "alerts off with demand held clears the streak")
        streak.resetBreaches()
        streakCheck()
        streakCheck()
        precondition(streakCalls == 0, "stopping the module clears the streak")
        streakCheck()
        precondition(streakCalls == 1)

        var diskCalls = 0
        let diskAlerts = MonitorAlerts { _ in diskCalls += 1 }
        let diskRules: [MonitorAlertRule.Metric: MonitorAlertRule] = [
            .diskFree: .init(direction: .below, threshold: 10, recoverValue: 15, sustainCount: 1)
        ]
        let writable = DiskVolume(name: "Data", mountPath: "/", total: 100, available: 50)
        let image = DiskVolume(name: "Image", mountPath: "/Volumes/Image", total: 100,
                               available: 0, isReadOnly: true)
        diskAlerts.evaluate(MonitorSnapshot(volumes: [writable, image]), rules: diskRules,
                            enabled: true, demand: 1, at: Date())
        precondition(diskCalls == 0)
        let full = DiskVolume(name: "Data", mountPath: "/", total: 100, available: 1)
        diskAlerts.evaluate(MonitorSnapshot(volumes: [full, image]), rules: diskRules,
                            enabled: true, demand: 1, at: Date())
        precondition(diskCalls == 1)
        print("PASS: threshold crossing, hysteresis, cooldown, disabled and no-demand gating")
    }
}
