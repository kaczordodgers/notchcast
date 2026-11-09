import Foundation

extension NotchcastFeature.Descriptor {
    static let killProcess = Self(
        title: String(localized: "Kill Process", table: "Notchcast"),
        subtitle: String(localized: "Adds a command to stop a process.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: true
    )
}
