import Foundation

extension NotchcastFeature.Descriptor {
    static let privacyChoices = Self(
        title: String(localized: "Privacy Choices", table: "Notchcast"),
        subtitle: String(localized: "Choose macOS privacy restrictions.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true,
        usesSystemToolsHelper: true
    )
}
