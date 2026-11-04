import SwiftUI

struct NotchcastSystemSettingsSection: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            ForEach(NotchcastFeature.allCases.filter { $0.isSystemFeature && $0 != .monitorAlerts }, id: \.self) { feature in
                Toggle(isOn: Binding(
                    get: { preferences.isOn(feature) }, set: { preferences.set(feature, $0) })) {
                    SettingsRowTitle(.notchcastMonitor, verbatim: feature.title)
                    Text(feature.subtitle)
                    if feature != .systemMonitor && feature != .fanControl && feature != .keepAwake,
                       NotchcastCore.battery.needsHelperUpdate {
                        Text("Needs the Notchcast helper update")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsEnabled(feature != .fanControl || preferences.isOn(.systemMonitor))
            }
            Picker(selection: $preferences.fanMode) {
                Text("Auto").tag("auto")
                Text("Medium").tag("medium")
                Text("Max").tag("max")
            } label: {
                SettingsRowTitle(.notchcastFanMode, "Fan mode")
            }
            .settingsEnabled(preferences.isOn(.systemMonitor) && preferences.isOn(.fanControl))
            Picker(selection: $preferences.batteryChargePercent) {
                ForEach(NotchcastPreferences.chargeLimits, id: \.self) { percent in
                    Text(Double(percent) / 100, format: .percent).tag(percent)
                }
            } label: {
                SettingsRowTitle(.notchcastChargePercent, "Charge limit percent")
            }
            .settingsEnabled(preferences.isOn(.batteryChargeLimit))
            Picker(selection: $preferences.keepAwakeMinutes) {
                ForEach(NotchcastPreferences.awakeDurations, id: \.self) { minutes in
                    Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes])))
                        .tag(minutes)
                }
            } label: {
                SettingsRowTitle(.notchcastAwakeDuration, "Keep-awake duration")
            }
            .settingsEnabled(preferences.isOn(.keepAwake))
            if let failure = NotchcastCore.battery.failure {
                Text(failure.localizedDescription).foregroundStyle(.secondary)
            }
            if !NotchcastCore.battery.helperInstalled {
                Text("The privileged helper is not installed.").foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding(get: { preferences.isOn(.monitorAlerts) },
                                 set: { preferences.set(.monitorAlerts, $0) })) {
                SettingsRowTitle(.notchcastAlerts, "Monitor Alerts")
                Text(NotchcastFeature.monitorAlerts.subtitle)
            }
            .settingsEnabled(preferences.isOn(.systemMonitor))
            Group {
                Stepper(value: $preferences.monitorCPU, in: 10...100, step: 5) {
                    SettingsRowTitle(.notchcastAlertCPU, "CPU usage threshold")
                    Text(Double(preferences.monitorCPU) / 100, format: .percent)
                }
                Stepper(value: $preferences.monitorTemperature, in: 40...110, step: 5) {
                    SettingsRowTitle(.notchcastAlertTemperature, "CPU temperature threshold")
                    Text(Measurement(value: Double(preferences.monitorTemperature), unit: UnitTemperature.celsius),
                         format: .measurement(width: .abbreviated, usage: .asProvided))
                }
                Picker(selection: $preferences.monitorMemory) {
                    Text("Warning").tag(0)
                    Text("Critical").tag(1)
                } label: { SettingsRowTitle(.notchcastAlertMemory, "Memory pressure threshold") }
                Stepper(value: $preferences.monitorDisk, in: 1...50) {
                    SettingsRowTitle(.notchcastAlertDisk, "Disk free threshold")
                    Text(Double(preferences.monitorDisk) / 100, format: .percent)
                }
                Stepper(value: $preferences.monitorBattery, in: 1...50) {
                    SettingsRowTitle(.notchcastAlertBattery, "Battery threshold")
                    Text(Double(preferences.monitorBattery) / 100, format: .percent)
                }
            }
            .settingsEnabled(preferences.isOn(.systemMonitor) && preferences.isOn(.monitorAlerts))
        } header: {
            SettingsSectionHeader(.notchcastMonitor)
        }
        .onAppear { NotchcastCore.battery.refreshHelper() }
    }
}
