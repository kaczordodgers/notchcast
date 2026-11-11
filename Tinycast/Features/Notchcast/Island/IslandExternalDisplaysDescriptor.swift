import Foundation

extension NotchcastFeature.Descriptor {
    static let islandExternalDisplays = Self(
        title: String(localized: "External Displays", table: "Notchcast"),
        subtitle: String(localized: "Show the island on external displays.", table: "Notchcast"),
        group: .islandOptions,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
