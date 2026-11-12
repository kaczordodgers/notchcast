extension BatteryModule: NotchcastRegistrant {
    static let shared = BatteryModule(preferences: .shared, runner: .live)

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [], requiresAny: NotchcastFeature.batteryModule, module: shared)]
    }
}
