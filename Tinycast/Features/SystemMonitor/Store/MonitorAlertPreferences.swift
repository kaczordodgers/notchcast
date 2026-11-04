import Foundation

extension NotchcastPreferences {
    var monitorAlertRules: [MonitorAlertRule.Metric: MonitorAlertRule] {
        [
            .cpu: .init(direction: .above, threshold: Double(monitorCPU),
                        recoverValue: Double(monitorCPU - 10)),
            .cpuTemperature: .init(direction: .above, threshold: Double(monitorTemperature),
                                   recoverValue: Double(monitorTemperature - 5)),
            .memoryPressure: .init(direction: .above, threshold: Double(monitorMemory), recoverValue: 0),
            .diskFree: .init(direction: .below, threshold: Double(monitorDisk),
                             recoverValue: Double(monitorDisk + 5)),
            .battery: .init(direction: .below, threshold: Double(monitorBattery),
                            recoverValue: Double(monitorBattery + 5)),
            .batteryTemperature: .init(direction: .above, threshold: Double(monitorBatteryTemperature),
                                       recoverValue: Double(monitorBatteryTemperature - 5))
        ]
    }
}
