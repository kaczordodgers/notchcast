import Foundation

extension NotchcastFeature.Descriptor {
    static let islandFullScreen = Self(
        title: String(localized: "Full-Screen Apps", table: "Notchcast"),
        subtitle: String(localized: "Show the island over full-screen apps.", table: "Notchcast"),
        group: .islandOptions,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
