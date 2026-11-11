import Foundation

extension NotchcastFeature.Descriptor {
    static let batteryCalibration = Self(
        title: String(localized: "Battery Calibration", table: "Notchcast"),
        subtitle: String(localized: "Run a full battery calibration cycle.", table: "Notchcast"),
        group: .systemTools,
        defaultEnabled: false,
        backedUp: false,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: true,
        isSystemTweak: false
    )
}
