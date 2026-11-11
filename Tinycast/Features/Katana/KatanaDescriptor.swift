import Foundation

extension NotchcastFeature.Descriptor {
    static let katana = Self(
        title: String(localized: "Katana", table: "Notchcast"),
        subtitle: String(localized: "Switch Katana amp channels from the launcher.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
