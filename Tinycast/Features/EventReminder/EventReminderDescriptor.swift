import Foundation

extension NotchcastFeature.Descriptor {
    static let eventReminder = Self(
        title: String(localized: "Event Reminders", table: "Notchcast"),
        subtitle: String(localized: "Show calendar alerts in the island.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [.calendars],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
