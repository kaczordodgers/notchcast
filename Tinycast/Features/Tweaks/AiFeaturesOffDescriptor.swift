import Foundation

extension NotchcastFeature.Descriptor {
    static let aiFeaturesOff = Self(
        title: String(localized: "AI Features Off", table: "Notchcast"),
        subtitle: String(localized: "Review a profile disabling all Apple intelligence features.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true,
        usesSystemToolsHelper: true
    )
}
