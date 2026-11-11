import Foundation

extension NotchcastFeature.Descriptor {
    static let islandLiveActivities = Self(
        title: String(localized: "Live Activities", table: "Notchcast"),
        subtitle: String(localized: "Show live activities in the island.", table: "Notchcast"),
        group: .islandOptions,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
