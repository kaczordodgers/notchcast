import Foundation

/// Each alert threshold's bounds and default, typed once: the backup and the settings rows read them here.
nonisolated enum MonitorAlertThreshold {
    case cpu, temperature, memory, disk, battery, batteryTemperature

    var range: ClosedRange<Int> { limits.range }
    var defaultValue: Int { limits.defaultValue }
    var backupValue: NotchcastFeature.BackupValue { .integer(Double(range.lowerBound)...Double(range.upperBound)) }

    private var limits: (range: ClosedRange<Int>, defaultValue: Int) {
        switch self {
        case .cpu: (10...100, 90)
        case .temperature: (40...110, 90)
        case .memory: (0...1, 1)
        case .disk: (1...50, 10)
        case .battery: (1...50, 15)
        case .batteryTemperature: (30...60, 40)
        }
    }
}

extension NotchcastFeature.BackupKeys {
    static let monitorAlerts = Self(allowed: [
        NotchcastPreferences.monitorCPUKey: MonitorAlertThreshold.cpu.backupValue,
        NotchcastPreferences.monitorTemperatureKey: MonitorAlertThreshold.temperature.backupValue,
        NotchcastPreferences.monitorMemoryKey: MonitorAlertThreshold.memory.backupValue,
        NotchcastPreferences.monitorDiskKey: MonitorAlertThreshold.disk.backupValue,
        NotchcastPreferences.monitorBatteryKey: MonitorAlertThreshold.battery.backupValue,
        NotchcastPreferences.monitorBatteryTemperatureKey: MonitorAlertThreshold.batteryTemperature.backupValue,
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
