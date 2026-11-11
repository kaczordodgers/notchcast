import Foundation

extension NotchcastFeature.Descriptor {
    static let settingsBackup = Self(
        title: String(localized: "Settings Backup", table: "Notchcast"),
        subtitle: String(localized: "Back up safe Notchcast preferences daily.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
