import Foundation

extension NotchcastFeature.Descriptor {
    static let notificationCleanup = Self(
        title: String(localized: "Notification Cleanup", table: "Notchcast"),
        subtitle: String(localized: "Dismiss disk-ejection alerts automatically.", table: "Notchcast"),
        group: .tweaks,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: true,
        usesSystemToolsHelper: true
    )
}
