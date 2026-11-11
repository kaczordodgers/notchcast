import Foundation

extension NotchcastFeature.Descriptor {
    static let waitingAlerts = Self(
        title: String(localized: "Waiting-for-you alerts", table: "Notchcast"),
        subtitle: String(localized: "Notify when an agent needs approval or an answer.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
