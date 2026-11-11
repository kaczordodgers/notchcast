import Foundation

extension NotchcastFeature.Descriptor {
    static let torrentsKeepSharing = Self(
        title: String(localized: "Keep sharing until ratio 1.0", table: "Notchcast"),
        subtitle: String(localized: "Upload as much as you download before stopping.", table: "Notchcast"),
        group: .torrents,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.torrents],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
