import Foundation

@MainActor
enum ForkSettingsBackupRestore {
    static func snapshot(_ preferences: NotchcastPreferences) -> [String: Any] {
        var values: [String: Any] = ["monitorCPU": preferences.monitorCPU,
         "monitorTemperature": preferences.monitorTemperature,
         "monitorMemory": preferences.monitorMemory,
         "monitorDisk": preferences.monitorDisk,
         "monitorBattery": preferences.monitorBattery,
         "keepAwakeMinutes": preferences.keepAwakeMinutes,
         "islandHoverDelay": preferences.islandHoverDelay.rawValue,
         "greenMaximizeExcludedApps": preferences.greenMaximizeExcludedApps]
        for feature in NotchcastFeature.allCases where ForkSettingsBackupSchema.allowed[feature.rawValue] != nil {
            values[feature.rawValue] = preferences.isOn(feature)
        }
        return values
    }

    static func apply(_ values: [String: Any], to preferences: NotchcastPreferences) throws {
        try ForkSettingsBackupEngine.validate(values)
        for feature in NotchcastFeature.allCases {
            if let enabled = values[feature.rawValue] as? Bool { preferences.set(feature, enabled) }
        }
        if let value = values["greenMaximizeExcludedApps"] as? String { preferences.greenMaximizeExcludedApps = value }
        if let number = values["monitorCPU"] as? NSNumber { preferences.monitorCPU = number.intValue }
        if let number = values["monitorTemperature"] as? NSNumber { preferences.monitorTemperature = number.intValue }
        if let number = values["monitorMemory"] as? NSNumber { preferences.monitorMemory = number.intValue }
        if let number = values["monitorDisk"] as? NSNumber { preferences.monitorDisk = number.intValue }
        if let number = values["monitorBattery"] as? NSNumber { preferences.monitorBattery = number.intValue }
        if let number = values["keepAwakeMinutes"] as? NSNumber { preferences.keepAwakeMinutes = number.intValue }
        if let number = values["islandHoverDelay"] as? NSNumber,
           let delay = NotchcastPreferences.HoverDelay(rawValue: number.doubleValue) {
            preferences.islandHoverDelay = delay
        }
    }
}
