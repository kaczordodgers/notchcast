import Foundation

extension NotchcastFeature.Descriptor {
    static let privacyChoices = Self(
        title: String(localized: "Privacy Choices", table: "Notchcast"),
        subtitle: String(localized: "Review a profile disabling analytics, personalized ads, web results and suggestions.", table: "Notchcast"),
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
