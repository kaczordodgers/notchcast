import Foundation

extension NotchcastFeature.Descriptor {
    static let dayCalendar = Self(
        title: String(localized: "Calendar"),
        subtitle: String(localized: "Calendar events on the Day page.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [.calendars],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
