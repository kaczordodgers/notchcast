import Foundation

extension NotchcastFeature.Descriptor {
    static let clearNotifications = Self(
        title: String(localized: "Clear Notifications", table: "Notchcast"),
        subtitle: String(localized: "Clear notifications from Notification Center. Requires English system language.", table: "Notchcast"),
        group: .launcher,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [.accessibility],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
