extension BatteryModule: NotchcastRegistrant {
    static let shared = BatteryModule(preferences: .shared, runner: .live)

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [], requiresAny: [
            .batteryChargeLimit, .batterySailing, .batteryHeatProtection, .batteryCalibration, .keepAwake, .lidClosedAwake,
        ], module: shared)]
    }
}
