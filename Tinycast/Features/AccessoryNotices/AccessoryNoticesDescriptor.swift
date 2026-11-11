import Foundation

extension NotchcastFeature.Descriptor {
    static let accessoryNotices = Self(
        title: String(localized: "Accessory notices", table: "Notchcast"),
        subtitle: String(localized: "Show accessory connections and low battery notices.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [.bluetooth],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
