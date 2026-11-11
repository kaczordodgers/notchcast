import Foundation

extension NotchcastFeature.Descriptor {
    static let dockTweaks = Self(
        title: String(localized: "Dock and windows", table: "Notchcast"),
        subtitle: String(localized: "Changes Dock preferences and restarts Dock after confirmation.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true
    )
}
