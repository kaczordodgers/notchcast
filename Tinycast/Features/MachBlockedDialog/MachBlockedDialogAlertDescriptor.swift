import Foundation

extension NotchcastFeature.Descriptor {
    static let machBlockedDialogAlert = Self(
        title: String(localized: "Other Mac Dialog Alerts", table: "Notchcast"),
        subtitle: String(localized: "Check for system dialogs on the paired Mac on demand.", table: "Notchcast"),
        group: .system,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.island, .islandStatusMessages, .machLink],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
