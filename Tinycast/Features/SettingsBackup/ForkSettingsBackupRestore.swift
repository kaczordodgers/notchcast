import Foundation

@MainActor
enum ForkSettingsBackupRestore {
    static func snapshot(_ preferences: NotchcastPreferences) -> [String: Any] {
        var values: [String: Any] = [:]
        for field in fields { values[field.key] = field.read(preferences) }
        for feature in switches { values[feature.rawValue] = carried(feature, preferences.isOn(feature)) }
        return values
    }

    static func apply(_ values: [String: Any], to preferences: NotchcastPreferences) throws {
        try ForkSettingsBackupEngine.validate(values)
        for feature in switches {
            if let enabled = values[feature.rawValue] as? Bool { preferences.set(feature, carried(feature, enabled)) }
        }
        for field in fields {
            if let value = values[field.key] { field.write(preferences, value) }
        }
    }

    private static let switches = NotchcastFeature.allCases.filter {
        ForkSettingsBackupSchema.allowed[$0.rawValue] != nil
    }

    /// An unwired switch is carried as off both ways, so a restore cannot enable a hidden feature.
    private static func carried(_ feature: NotchcastFeature, _ enabled: Bool) -> Bool { feature.isWired && enabled }

    private struct Field {
        let key: String
        let read: (NotchcastPreferences) -> Any
        let write: (NotchcastPreferences, Any) -> Void
    }

    private static let fields = [
        number("monitorCPU", \.monitorCPU),
        number("monitorTemperature", \.monitorTemperature),
        number("monitorMemory", \.monitorMemory),
        number("monitorDisk", \.monitorDisk),
        number("monitorBattery", \.monitorBattery),
        number("monitorBatteryTemperature", \.monitorBatteryTemperature),
        Field(key: "islandHoverDelay", read: { $0.islandHoverDelay.rawValue }, write: { preferences, value in
            guard let number = value as? NSNumber,
                  let delay = NotchcastPreferences.HoverDelay(rawValue: number.doubleValue) else { return }
            preferences.islandHoverDelay = delay
        }),
        text("greenMaximizeExcludedApps", \.greenMaximizeExcludedApps),
        text("buildStatsPath", \.buildStatsPath),
        text("backupStatusPath", \.backupStatusPath),
    ]

    private static func number(_ key: String, _ path: ReferenceWritableKeyPath<NotchcastPreferences, Int>) -> Field {
        Field(key: key, read: { $0[keyPath: path] }, write: { preferences, value in
            if let number = value as? NSNumber { preferences[keyPath: path] = number.intValue }
        })
    }

    private static func text(_ key: String, _ path: ReferenceWritableKeyPath<NotchcastPreferences, String>) -> Field {
        Field(key: key, read: { $0[keyPath: path] }, write: { preferences, value in
            if let text = value as? String { preferences[keyPath: path] = text }
        })
    }
}
