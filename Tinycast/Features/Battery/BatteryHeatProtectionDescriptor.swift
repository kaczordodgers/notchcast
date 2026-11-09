import Foundation

extension NotchcastFeature.Descriptor {
    static let batteryHeatProtection = Self(
        title: String(localized: "Battery Heat Protection", table: "Notchcast"),
        subtitle: String(localized: "Pause charging when the battery is hot.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
