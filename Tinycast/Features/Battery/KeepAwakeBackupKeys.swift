import Foundation

extension NotchcastFeature.BackupKeys {
    static let keepAwake = Self(allowed: [:], excluded: [
        NotchcastPreferences.keepAwakeMinutesKey,
    ])
}
