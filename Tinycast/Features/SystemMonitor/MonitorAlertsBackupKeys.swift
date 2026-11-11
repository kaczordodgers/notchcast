import Foundation

extension NotchcastFeature.BackupKeys {
    static let monitorAlerts = Self(allowed: Dictionary(uniqueKeysWithValues: MonitorThreshold.all.map {
        ($0.key, NotchcastFeature.BackupValue.integer(Double($0.range.lowerBound)...Double($0.range.upperBound)))
    }), excluded: [])
}
