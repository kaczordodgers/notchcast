import Foundation

extension NotchcastFeature.BackupKeys {
    static let monitorAlerts = Self(allowed: [
        "monitorCPU": .integer(10...100),
        "monitorTemperature": .integer(40...110),
        "monitorMemory": .integer(0...1),
        "monitorDisk": .integer(1...50),
        "monitorBattery": .integer(1...50),
        "monitorBatteryTemperature": .integer(30...60),
    ], excluded: [])
}
