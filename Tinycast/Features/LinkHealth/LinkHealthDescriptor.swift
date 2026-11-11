import Foundation

extension NotchcastFeature.Descriptor {
    static let linkHealth = Self(
        title: String(localized: "Link Health", table: "Notchcast"),
        subtitle: String(localized: "Notify when the paired Mac disconnects or reconnects.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.machLink],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
