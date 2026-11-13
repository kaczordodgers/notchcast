import Foundation

extension NotchcastFeature.Descriptor {
    static let batterySailing = Self(
        title: String(localized: "Battery Sailing", table: "Notchcast"),
        subtitle: String(localized:
            "Pause charging above the charge limit without disconnecting the adapter.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
