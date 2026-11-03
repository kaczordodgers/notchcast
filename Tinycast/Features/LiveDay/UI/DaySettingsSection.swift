import SwiftUI

struct DaySettingsSection: View {
    let weather: DayWeatherStore
    let markets: DayMarketsStore
    private let preferences = NotchcastPreferences.shared
    @State private var symbols = ""

    var body: some View {
        if preferences.isOn(.dayWeather) || preferences.isOn(.dayMarkets) {
            Section {
                if preferences.isOn(.dayWeather) { DayCityField(store: weather) }
                if preferences.isOn(.dayMarkets) {
                    TextField(text: $symbols) {
                        SettingsRowTitle(.notchcastDay, "Symbols")
                        Text("Yahoo Finance symbols, separated by commas.")
                    }
                    .onAppear { symbols = markets.symbols.joined(separator: ", ") }
                    .onSubmit(saveSymbols)
                    .onDisappear(perform: saveSymbols)
                }
            } header: {
                SettingsSectionHeader(.notchcastDay)
            }
            .settingsEnabled(preferences.isOn(.island))
        }
    }

    private func saveSymbols() {
        let updated = symbols.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        if updated != markets.symbols { markets.setSymbols(updated) }
    }
}
