import SwiftUI

struct NotchcastExtrasSection: View {
    static let features: [NotchcastFeature] = [
        .lowDiskWarning,
        .systemNotices,
        .volumeLevels,
        .displayBrightness,
        .quitProtection,
        .liveTimers,
        .dayCalendar,
        .dayWeather,
        .dayMarkets,
    ]

    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            ForEach(Self.features, id: \.self) { feature in
                Toggle(isOn: Binding(
                    get: { preferences.isOn(feature) },
                    set: { preferences.set(feature, $0) })) {
                    SettingsRowTitle(.notchcastExtras, verbatim: feature.title)
                    Text(feature.subtitle)
                }
                .settingsEnabled(preferences.isOn(.island) || !feature.needsIsland)
            }
        } header: {
            SettingsSectionHeader(.notchcastExtras)
        }

        BrightnessSettingsSection(controller: NotchcastCore.brightness.controller)
        QuitProtectionSettingsSection(store: NotchcastCore.quitProtection)
        TimerSettingsSection(store: NotchcastCore.timers.store)
        DaySettingsSection(weather: NotchcastCore.weather.store, markets: NotchcastCore.markets.store)
    }
}
