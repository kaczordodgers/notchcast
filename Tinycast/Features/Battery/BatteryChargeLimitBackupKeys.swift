import Foundation

extension NotchcastFeature.BackupKeys {
    static let batteryChargeLimit = Self(allowed: [:], excluded: [
        "batteryChargePercent",
    ])
}
