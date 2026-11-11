import Foundation

extension NotchcastFeature.BackupKeys {
    static let fanControl = Self(allowed: [:], excluded: [
        NotchcastPreferences.fanModeKey,
    ])
}
