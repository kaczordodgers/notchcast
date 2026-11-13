import Foundation

extension NotchcastFeature.Descriptor {
    static let batteryCalibration = Self(
        title: String(localized: "Battery Calibration", table: "Notchcast"),
        subtitle: String(localized: "Charge to 100%, unplug to 10%, recharge to 100%, then unplug to the limit and reconnect.",
                         table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
