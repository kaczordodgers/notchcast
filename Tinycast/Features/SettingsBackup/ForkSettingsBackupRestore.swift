import Foundation

@MainActor
enum ForkSettingsBackupRestore {
    static func snapshot(_ preferences: NotchcastPreferences) -> [String: Any] {
        ["monitorCPU": preferences.monitorCPU,
         "monitorTemperature": preferences.monitorTemperature,
         "monitorMemory": preferences.monitorMemory,
         "monitorDisk": preferences.monitorDisk,
         "monitorBattery": preferences.monitorBattery,
         "keepAwakeMinutes": preferences.keepAwakeMinutes,
         "islandHoverDelay": preferences.islandHoverDelay.rawValue]
    }

    static func apply(_ values: [String: Any], to preferences: NotchcastPreferences) {
        if let n = values["monitorCPU"] as? NSNumber { preferences.monitorCPU = n.intValue }
        if let n = values["monitorTemperature"] as? NSNumber { preferences.monitorTemperature = n.intValue }
        if let n = values["monitorMemory"] as? NSNumber { preferences.monitorMemory = n.intValue }
        if let n = values["monitorDisk"] as? NSNumber { preferences.monitorDisk = n.intValue }
        if let n = values["monitorBattery"] as? NSNumber { preferences.monitorBattery = n.intValue }
        if let n = values["batteryChargePercent"] as? NSNumber { preferences.batteryChargePercent = n.intValue }
        if let n = values["keepAwakeMinutes"] as? NSNumber { preferences.keepAwakeMinutes = n.intValue }
        if let n = values["islandHoverDelay"] as? NSNumber {
            preferences.islandHoverDelay = NotchcastPreferences.HoverDelay(rawValue: n.doubleValue) ?? .standard
        }
    }
}
