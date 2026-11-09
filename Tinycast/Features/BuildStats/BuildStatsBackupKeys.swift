import Foundation

extension NotchcastFeature.BackupKeys {
    static let buildStats = Self(allowed: [
        "buildStatsPath": .string(4096),
    ], excluded: [])
}
