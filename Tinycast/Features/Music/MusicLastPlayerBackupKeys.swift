import Foundation

extension NotchcastFeature.BackupKeys {
    static let musicLastPlayer = Self(allowed: [:], excluded: [
        LastPlayer.key,
    ])
}
