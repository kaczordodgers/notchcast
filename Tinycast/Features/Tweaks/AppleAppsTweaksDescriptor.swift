import Foundation

extension NotchcastFeature.Descriptor {
    static let appleAppsTweaks = Self(
        title: String(localized: "Apple apps", table: "Notchcast"),
        subtitle: String(localized: "macOS requires your approval to install this restriction; remove it in System Settings.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true
    )
}
