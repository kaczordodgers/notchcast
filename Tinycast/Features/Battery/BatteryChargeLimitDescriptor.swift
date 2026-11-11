import Foundation

extension NotchcastFeature.Descriptor {
    static let batteryChargeLimit = Self(
        title: String(localized: "Charge Limit", table: "Notchcast"),
        subtitle: String(localized: "Stop charging at the selected limit.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
