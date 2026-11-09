import Foundation

extension NotchcastFeature.Descriptor {
    static let musicLastPlayer = Self(
        title: String(localized: "Resume last player", table: "Notchcast"),
        subtitle: String(localized: "Send playback controls to the last active player.", table: "Notchcast"),
        group: .music,
        defaultEnabled: true,
        dependencies: [.island, .musicNowPlaying],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
