enum BatterySettingsPolicy {
    static func chargeLimitAvailable(enabled: Bool, nativeLimitAvailable: Bool) -> Bool {
        enabled || nativeLimitAvailable
    }
}
