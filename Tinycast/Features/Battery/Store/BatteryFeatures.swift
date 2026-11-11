extension NotchcastFeature {
    /// The switches that hold the charger off; each needs hardware charging control.
    static let batteryChargingControl: [NotchcastFeature] = [
        .batterySailing,
        .batteryHeatProtection,
        .batteryCalibration,
    ]

    static let batteryModule: [NotchcastFeature] = [.batteryChargeLimit] + batteryChargingControl + [
        .keepAwake,
        .lidClosedAwake,
    ]
}

extension NotchcastPreferences {
    var holdsBatteryCharging: Bool { NotchcastFeature.batteryChargingControl.contains(where: isOn) }
}
