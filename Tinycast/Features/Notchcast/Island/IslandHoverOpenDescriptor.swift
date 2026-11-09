import Foundation

extension NotchcastFeature.Descriptor {
    static let islandHoverOpen = Self(
        title: String(localized: "Open on Hover", table: "Notchcast"),
        subtitle: String(localized: "Open the island when the pointer hovers over it.", table: "Notchcast"),
        group: .islandOptions,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
