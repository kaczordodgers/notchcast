import Foundation

extension NotchcastFeature.Descriptor {
    static let finderTweaks = Self(
        title: String(localized: "Finder", table: "Notchcast"),
        subtitle: String(localized: "Changes Finder preferences and restarts Finder after confirmation.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true
    )
}
