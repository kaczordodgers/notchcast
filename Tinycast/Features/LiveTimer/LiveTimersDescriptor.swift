import Foundation

extension NotchcastFeature.Descriptor {
    static let liveTimers = Self(
        title: String(localized: "Timers", table: "Notchcast"),
        subtitle: String(localized: "Countdowns and alarms in the island.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
