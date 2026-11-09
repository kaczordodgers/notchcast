import Foundation

extension NotchcastFeature.Descriptor {
    static let backupBrowseRestore = Self(
        title: String(localized: "Browse and Restore Backups", table: "Notchcast"),
        subtitle: String(localized: "Browse snapshots and restore into a new Downloads folder.", table: "Notchcast"),
        group: .system,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
