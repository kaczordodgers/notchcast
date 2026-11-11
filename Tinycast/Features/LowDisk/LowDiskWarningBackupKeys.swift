import Foundation

extension NotchcastFeature.BackupKeys {
    static let lowDiskWarning = Self(allowed: [:], excluded: [
        LowDiskManager.spellKey,
    ])
}
