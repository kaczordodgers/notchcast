import Foundation

extension NotchcastFeature.BackupKeys {
    static let microphoneMute = Self(allowed: [:], excluded: [
        "microphone.muted",
        "microphone.muted.restore",
    ])
}
