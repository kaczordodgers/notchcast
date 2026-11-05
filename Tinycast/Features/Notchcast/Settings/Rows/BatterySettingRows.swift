import SwiftUI
import AppKit

struct NotchcastChargePercentSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Picker(selection: $preferences.batteryChargePercent) {
            ForEach(NotchcastPreferences.chargeLimits, id: \.self) { percent in
                Text(Double(percent) / 100, format: .percent).tag(percent)
            }
        } label: {
            SettingsRowTitle(.notchcastChargePercent, LocalizedStringResource("Charge limit percent", table: "Notchcast"))
            if let limit = NotchcastCore.battery.nativeLimit {
                Text(Double(limit) / 100, format: .percent)
            } else if NotchcastCore.battery.nativeLimitAvailable {
                Text("Off")
            }
        }
    }
}

struct NotchcastAwakeDurationSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        Picker(selection: $preferences.keepAwakeMinutes) {
            ForEach(NotchcastPreferences.awakeDurations, id: \.self) { minutes in
                Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes])))
                    .tag(minutes)
            }
        } label: {
            SettingsRowTitle(.notchcastAwakeDuration, LocalizedStringResource("Keep-awake duration", table: "Notchcast"))
        }
    }
}

struct NotchcastBatteryStatusSettingRow: View {
    let feature: NotchcastFeature

    var body: some View {
        Group {
            if feature == .batterySailing || feature == .batteryHeatProtection
                || feature == .batteryCalibration,
                NotchcastCore.battery.chargingUnsupported
            {
                Text("Not supported on this Mac", tableName: "Notchcast").foregroundStyle(.secondary)
            }
            if feature != .systemMonitor && feature != .fanControl && feature != .keepAwake,
                NotchcastCore.battery.needsHelperUpdate
                    || (feature == .batteryChargeLimit && !NotchcastCore.battery.nativeLimitAvailable)
            {
                Text("Needs the Notchcast helper update", tableName: "Notchcast").foregroundStyle(.secondary)
            }
            // Mac-wide helper state shows once, under the charge limit.
            if feature == .batteryChargeLimit, let failure = NotchcastCore.battery.failure {
                if failure as? RootHelperClient.Failure == .reinstallRequired {
                    Text("Needs the Notchcast helper update", tableName: "Notchcast").foregroundStyle(.secondary)
                } else {
                    Text(failure.localizedDescription).foregroundStyle(.secondary)
                }
            }
            if feature == .batteryChargeLimit, !NotchcastCore.battery.helperInstalled {
                Text("The privileged helper is not installed.", tableName: "Notchcast").foregroundStyle(.secondary)
            }
        }
        .onAppear { if feature == .batteryChargeLimit { NotchcastCore.battery.refreshHelper() } }
    }
}

struct NotchcastAccessoryReadingsSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared
    @State private var readings: [BatteryPeripheralReading] = []

    private var enabled: Bool {
        preferences.isOn(.systemMonitor) && preferences.isOn(.accessoryBatteries)
    }

    var body: some View {
        Group {
            if enabled {
                ForEach(readings, id: \.id) { reading in
                    LabeledContent {
                        HStack {
                            Text(reading.percent / 100, format: .percent)
                            if reading.isCharging == true {
                                Image(systemName: "bolt.fill").accessibilityLabel(String(localized: "Charging", table: "Notchcast"))
                            }
                        }
                    } label: {
                        Text(reading.name)
                    }
                }
            }
        }
        .task(id: enabled) { await refresh() }
    }

    private func refresh() async {
        readings = []
        guard enabled else { return }
        while !Task.isCancelled {
            let sample = await Self.sample()
            guard !Task.isCancelled, enabled else { return }
            readings = sample
            do {
                try await Task.sleep(for: .seconds(60))
            } catch { return }
        }
    }

    @concurrent private static func sample() async -> [BatteryPeripheralReading] {
        AccessoryBatteryRows.make(BatteryPeripheralService().read())
    }
}
