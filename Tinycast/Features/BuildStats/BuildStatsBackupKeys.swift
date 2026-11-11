import Foundation

extension NotchcastFeature.BackupKeys {
    static let buildStats = Self(allowed: [
        "buildStatsPath": .string(4096),
    ], excluded: [], snapshot: {
        ["buildStatsPath": NotchcastPreferences.shared.buildStatsPath]
    }, apply: { values in
        if let value = values["buildStatsPath"] as? String { NotchcastPreferences.shared.buildStatsPath = value }
    })
}
