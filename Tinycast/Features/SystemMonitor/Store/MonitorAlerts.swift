import Foundation

@MainActor
final class MonitorAlerts {
    private var rules: [MonitorAlertRule.Metric: MonitorAlertRule] = [:]
    private var configuration: [MonitorAlertRule.Metric: MonitorAlertRule] = [:]
    private let sink: (String) -> Void
    private var lastSampleID: UUID?

    init(sink: @escaping (String) -> Void = { _ in }) { self.sink = sink }

    func evaluate(
        _ snapshot: MonitorSnapshot, rules configured: [MonitorAlertRule.Metric: MonitorAlertRule],
        enabled: Bool, demand: Int, at now: Date
    ) {
        if !enabled || demand == 0 { resetBreaches() }
        guard enabled, demand > 0 else {
            lastSampleID = snapshot.id
            return
        }
        guard lastSampleID != snapshot.id else { return }
        lastSampleID = snapshot.id
        let pressure = snapshot.memory?.pressure.map { pressure in
            switch pressure { case .normal: 0.0; case .warning: 1.0; case .critical: 2.0 }
        }
        let diskFree = snapshot.volumes.filter { $0.total > 0 && !$0.isReadOnly }
            .map { Double($0.available) / Double($0.total) * 100 }.min()
        let values: [MonitorAlertRule.Metric: Double?] = [
            .cpu: snapshot.cpu?.usage?.totalPercent,
            .cpuTemperature: snapshot.sensors?.cpuTemperature,
            .memoryPressure: pressure, .diskFree: diskFree, .battery: snapshot.battery?.percent
        ]
        for metric in MonitorAlertRule.Metric.allCases {
            guard let rule = configured[metric], let value = values[metric] else { continue }
            if configuration[metric] != rule { rules[metric] = rule; configuration[metric] = rule }
            if rules[metric]?.evaluate(value ?? .nan, at: now) == .fire {
                sink(Self.title(metric))
            }
        }
    }

    func resetBreaches() {
        for metric in rules.keys { rules[metric]?.resetBreaches() }
    }

    private static func title(_ metric: MonitorAlertRule.Metric) -> String {
        switch metric {
        case .cpu: String(localized: "CPU usage threshold")
        case .cpuTemperature: String(localized: "CPU temperature threshold")
        case .memoryPressure: String(localized: "Memory pressure threshold")
        case .diskFree: String(localized: "Disk free threshold")
        case .battery, .batteryTemperature: String(localized: "Battery threshold")
        }
    }
}
