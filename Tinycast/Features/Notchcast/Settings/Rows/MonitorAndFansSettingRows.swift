import SwiftUI
import AppKit

struct NotchcastFanModeSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Picker(
            selection: Binding(
                get: { preferences.fanMode },
                set: {
                    NotchcastCore.setFanMode(FanControl.Mode(rawValue: $0) ?? .auto)
                })
        ) {
            Text("Auto").tag("auto")
            Text("Medium").tag("medium")
            Text("Max").tag("max")
        } label: {
            SettingsRowTitle(.notchcastFanMode, "Fan mode")
        }
        .settingsEnabled(preferences.isOn(.systemMonitor))
    }
}

struct NotchcastAlertCPUSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Stepper(value: $preferences.monitorCPU, in: 10...100, step: 5) {
            SettingsRowTitle(.notchcastAlertCPU, "CPU usage threshold")
            Text(Double(preferences.monitorCPU) / 100, format: .percent)
        }
        .settingsEnabled(preferences.isOn(.systemMonitor))
    }
}

struct NotchcastAlertTemperatureSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Stepper(value: $preferences.monitorTemperature, in: 40...110, step: 5) {
            SettingsRowTitle(.notchcastAlertTemperature, "CPU temperature threshold")
            Text(
                Measurement(value: Double(preferences.monitorTemperature), unit: UnitTemperature.celsius),
                format: .measurement(width: .abbreviated, usage: .asProvided))
        }
        .settingsEnabled(preferences.isOn(.systemMonitor))
    }
}

struct NotchcastAlertMemorySettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Picker(selection: $preferences.monitorMemory) {
            Text("Warning").tag(0)
            Text("Critical").tag(1)
        } label: {
            SettingsRowTitle(.notchcastAlertMemory, "Memory pressure threshold")
        }
        .settingsEnabled(preferences.isOn(.systemMonitor))
    }
}

struct NotchcastAlertDiskSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Stepper(value: $preferences.monitorDisk, in: 1...50) {
            SettingsRowTitle(.notchcastAlertDisk, "Disk free threshold")
            Text(Double(preferences.monitorDisk) / 100, format: .percent)
        }
        .settingsEnabled(preferences.isOn(.systemMonitor))
    }
}

struct NotchcastAlertBatterySettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Stepper(value: $preferences.monitorBattery, in: 1...50) {
            SettingsRowTitle(.notchcastAlertBattery, "Battery threshold")
            Text(Double(preferences.monitorBattery) / 100, format: .percent)
        }
        .settingsEnabled(preferences.isOn(.systemMonitor))
        Stepper(value: $preferences.monitorBatteryTemperature, in: 30...60) {
            SettingsRowTitle(.notchcastAlertBatteryTemperature, "Battery temperature threshold")
            Text(Measurement(value: Double(preferences.monitorBatteryTemperature), unit: UnitTemperature.celsius),
                 format: .measurement(width: .abbreviated, usage: .asProvided))
        }
        .settingsEnabled(preferences.isOn(.systemMonitor))
    }
}
