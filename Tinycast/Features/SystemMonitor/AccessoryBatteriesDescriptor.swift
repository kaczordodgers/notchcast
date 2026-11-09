import Foundation

extension NotchcastFeature.Descriptor {
    static let accessoryBatteries = Self(
        title: String(localized: "Accessory batteries", table: "Notchcast"),
        subtitle: String(localized: "Show connected accessory battery levels.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
