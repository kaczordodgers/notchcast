import Foundation

extension NotchcastFeature.Descriptor {
    static let machLink = Self(
        title: String(localized: "Mac Link", table: "Notchcast"),
        subtitle: String(localized: "Connect to a paired Mac on the local network.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
