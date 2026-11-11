import Foundation

extension NotchcastFeature.Descriptor {
    static let aiUsage = Self(
        title: String(localized: "AI Usage", table: "Notchcast"),
        subtitle: String(localized: "Read local AI usage on demand.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
