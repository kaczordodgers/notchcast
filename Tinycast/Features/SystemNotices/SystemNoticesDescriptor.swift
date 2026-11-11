import Foundation

extension NotchcastFeature.Descriptor {
    static let systemNotices = Self(
        title: String(localized: "System Notices", table: "Notchcast"),
        subtitle: String(localized: "Wi-Fi, Tailscale and low battery notices in the island.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
