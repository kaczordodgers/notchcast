import Foundation

extension NotchcastFeature.BackupKeys {
    static let monitorAlerts = Self(allowed: [
        NotchcastPreferences.monitorCPUKey: .integer(10...100),
        NotchcastPreferences.monitorTemperatureKey: .integer(40...110),
        NotchcastPreferences.monitorMemoryKey: .integer(0...1),
        NotchcastPreferences.monitorDiskKey: .integer(1...50),
        NotchcastPreferences.monitorBatteryKey: .integer(1...50),
        NotchcastPreferences.monitorBatteryTemperatureKey: .integer(30...60),
    ], excluded: [], snapshot: { NotchcastPreferences.shared.monitorAlertsBackupValues },
       apply: { NotchcastPreferences.shared.applyMonitorAlertsBackup($0) })
}

extension NotchcastPreferences {
    var monitorAlertsBackupValues: [String: Any] {
        [NotchcastPreferences.monitorCPUKey: monitorCPU,
         NotchcastPreferences.monitorTemperatureKey: monitorTemperature,
         NotchcastPreferences.monitorMemoryKey: monitorMemory,
         NotchcastPreferences.monitorDiskKey: monitorDisk,
         NotchcastPreferences.monitorBatteryKey: monitorBattery,
         NotchcastPreferences.monitorBatteryTemperatureKey: monitorBatteryTemperature]
    }

    func applyMonitorAlertsBackup(_ values: [String: Any]) {
        if let value = values[NotchcastPreferences.monitorCPUKey] as? NSNumber { monitorCPU = value.intValue }
        if let value = values[NotchcastPreferences.monitorTemperatureKey] as? NSNumber { monitorTemperature = value.intValue }
        if let value = values[NotchcastPreferences.monitorMemoryKey] as? NSNumber { monitorMemory = value.intValue }
        if let value = values[NotchcastPreferences.monitorDiskKey] as? NSNumber { monitorDisk = value.intValue }
        if let value = values[NotchcastPreferences.monitorBatteryKey] as? NSNumber { monitorBattery = value.intValue }
        if let value = values[NotchcastPreferences.monitorBatteryTemperatureKey] as? NSNumber {
            monitorBatteryTemperature = value.intValue
        }
    }
}
