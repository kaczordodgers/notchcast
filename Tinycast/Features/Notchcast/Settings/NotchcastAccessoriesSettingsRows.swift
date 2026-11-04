import SwiftUI

struct NotchcastAccessoriesSettingsRows: View {
    @Bindable private var preferences = NotchcastPreferences.shared
    @State private var readings: [BatteryPeripheralReading] = []

    private var enabled: Bool {
        preferences.isOn(.systemMonitor) && preferences.isOn(.accessoryBatteries)
    }

    var body: some View {
        Group {
            Toggle(isOn: Binding(
                get: { preferences.isOn(.accessoryBatteries) },
                set: { preferences.set(.accessoryBatteries, $0) })) {
                SettingsRowTitle(.notchcastAccessories, "Accessory batteries")
                Text(NotchcastFeature.accessoryBatteries.subtitle)
            }
            .settingsEnabled(preferences.isOn(.systemMonitor))
            .task(id: enabled) { await refresh() }
            if enabled {
                ForEach(readings, id: \.id) { reading in
                    LabeledContent {
                        HStack {
                            Text(reading.percent / 100, format: .percent)
                            if reading.isCharging == true {
                                Image(systemName: "bolt.fill").accessibilityLabel("Charging")
                            }
                        }
                    } label: {
                        Text(reading.name)
                    }
                }
            }
        }
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
