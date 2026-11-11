import Foundation

extension NotchcastFeature.Descriptor {
    static let aiFeaturesOff = Self(
        title: String(localized: "AI Features Off", table: "Notchcast"),
        subtitle: String(localized: "Choose which Apple intelligence features to disable.", table: "Notchcast"),
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
