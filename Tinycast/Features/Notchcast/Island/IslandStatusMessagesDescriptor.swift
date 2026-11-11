import Foundation

extension NotchcastFeature.Descriptor {
    static let islandStatusMessages = Self(
        title: String(localized: "Status Messages", table: "Notchcast"),
        subtitle: String(localized: "Show status messages in the island.", table: "Notchcast"),
        group: .islandOptions,
        defaultEnabled: true,
        backedUp: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
