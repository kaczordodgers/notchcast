import Foundation

extension NotchcastFeature.Descriptor {
    static let appearance = Self(
        title: String(localized: "Custom appearance", table: "Notchcast"),
        subtitle: String(localized: "Themes and surface styles for the launcher, dialogs and HUDs.", table: "Notchcast"),
        group: .appearance,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
