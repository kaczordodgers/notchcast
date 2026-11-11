import Foundation

extension NotchcastFeature.Descriptor {
    static let aiUsageOtherMac = Self(
        title: String(localized: "Other Mac AI Usage", table: "Notchcast"),
        subtitle: String(localized: "Include usage from the other Mac.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [.aiUsage, .machLink],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
