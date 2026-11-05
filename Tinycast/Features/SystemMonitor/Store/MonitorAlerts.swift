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
        let diskFree = snapshot.volumes.filter { $0.mountPath == "/" && $0.total > 0 && !$0.isReadOnly }
            .map { Double($0.available) / Double($0.total) * 100 }.min()
        let values: [MonitorAlertRule.Metric: Double?] = [
            .cpu: snapshot.cpu?.usage?.totalPercent,
            .cpuTemperature: snapshot.sensors?.cpuTemperature,
            .memoryPressure: pressure, .diskFree: diskFree, .battery: snapshot.battery?.percent,
            .batteryTemperature: snapshot.battery?.temperatureCelsius
        ]
        for metric in MonitorAlertRule.Metric.allCases {
            guard let rule = configured[metric], let value = values[metric] else { continue }
            if configuration[metric] != rule {
                var replacement = rule
                if let previous = rules[metric] { replacement.preserveCooldown(from: previous) }
                rules[metric] = replacement
                configuration[metric] = rule
            }
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
        case .cpu: String(localized: "CPU usage threshold", table: "Notchcast")
        case .cpuTemperature: String(localized: "CPU temperature threshold", table: "Notchcast")
        case .memoryPressure: String(localized: "Memory pressure threshold", table: "Notchcast")
        case .diskFree: String(localized: "Disk free threshold", table: "Notchcast")
        case .battery: String(localized: "Battery threshold", table: "Notchcast")
        case .batteryTemperature: String(localized: "Battery temperature threshold", table: "Notchcast")
        }
    }
}
