import Foundation

extension NotchcastFeature.Descriptor {
    static let backupRunNow = Self(
        title: String(localized: "Back Up Now", table: "Notchcast"),
        subtitle: String(localized: "Allow starting the configured backup job.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
