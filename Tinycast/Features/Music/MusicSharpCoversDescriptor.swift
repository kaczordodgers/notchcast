import Foundation

extension NotchcastFeature.Descriptor {
    static let musicSharpCovers = Self(
        title: String(localized: "Find sharp covers for Firefox and Zen", table: "Notchcast"),
        subtitle: String(localized: "Read the browser’s saved session on this Mac and send the song title and artist to Apple.",
                         table: "Notchcast"),
        group: .music,
        defaultEnabled: false,
        dependencies: [.island, .musicNowPlaying],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
