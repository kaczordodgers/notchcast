import Foundation

extension NotchcastFeature.BackupKeys {
    static let buildStats = Self(allowed: [
        NotchcastPreferences.buildStatsPathKey: .string(4096),
    ], excluded: [], snapshot: {
        [NotchcastPreferences.buildStatsPathKey: NotchcastPreferences.shared.buildStatsPath]
    }, apply: { values in
        guard let value = values[NotchcastPreferences.buildStatsPathKey] as? String else { return }
        NotchcastPreferences.shared.buildStatsPath = value
    })
}
