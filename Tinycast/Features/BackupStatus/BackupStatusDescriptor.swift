import Foundation

extension NotchcastFeature.Descriptor {
    static let backupStatus = Self(
        title: String(localized: "Backup Status", table: "Notchcast"),
        subtitle: String(localized: "Warns when backups fail or become stale.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
