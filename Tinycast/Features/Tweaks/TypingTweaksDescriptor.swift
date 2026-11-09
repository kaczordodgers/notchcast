import Foundation

extension NotchcastFeature.Descriptor {
    static let typingTweaks = Self(
        title: String(localized: "Typing", table: "Notchcast"),
        subtitle: String(localized: "Changes system preferences after confirmation; some changes require signing out.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true
    )
}
