import Foundation

extension NotchcastFeature.BackupKeys {
    static let microphoneMute = Self(allowed: [:], excluded: [
        MicrophoneMute.mutedKey,
        MicrophoneMute.restoreKey,
    ])
}
