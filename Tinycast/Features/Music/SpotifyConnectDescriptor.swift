import Foundation

extension NotchcastFeature.Descriptor {
    static let spotifyConnect = Self(
        title: String(localized: "Spotify Connect speaker", table: "Notchcast"),
        subtitle: String(localized: "Use this Mac as a Spotify playback device.", table: "Notchcast"),
        group: .music,
        defaultEnabled: false,
        dependencies: [.island, .musicNowPlaying],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
