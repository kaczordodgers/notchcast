import Foundation

extension NotchcastFeature.Descriptor {
    static let musicNowPlaying = Self(
        title: String(localized: "Show what is playing", table: "Notchcast"),
        subtitle: String(localized: "Show track information in the island.", table: "Notchcast"),
        group: .music,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
