import SwiftUI

struct NotchcastExtrasSection: View {
    static var features: [NotchcastFeature] {
        NotchcastFeature.allCases.filter { $0.settingsGroup == .activities }
    }

    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            ForEach(Self.features, id: \.self) { feature in
                Toggle(isOn: Binding(
                    get: { preferences.isOn(feature) },
                    set: { preferences.set(feature, $0) })) {
                    SettingsRowTitle(.notchcastActivities, verbatim: feature.title)
                    Text(feature.subtitle)
                }
                .settingsEnabled(preferences.isOn(.island) || !feature.needsIsland)
            }
        } header: {
            SettingsSectionHeader(.notchcastActivities)
        }

        TimerSettingsSection(store: NotchcastCore.timers.store)
        DaySettingsSection(weather: NotchcastCore.weather.store, markets: NotchcastCore.markets.store)
    }
}
