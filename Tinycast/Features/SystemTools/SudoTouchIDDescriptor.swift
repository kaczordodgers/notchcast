import Foundation

extension NotchcastFeature.Descriptor {
    static let sudoTouchID = Self(
        title: String(localized: "Touch ID for sudo", table: "Notchcast"),
        subtitle: String(localized: "Use Touch ID to authorize sudo.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true,
        usesSystemToolsHelper: true
    )
}
