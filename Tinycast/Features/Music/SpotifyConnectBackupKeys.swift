import Foundation

extension NotchcastFeature.BackupKeys {
    static let spotifyConnect = Self(allowed: [:], excluded: [
        "spotify.deviceName",
    ])
}
