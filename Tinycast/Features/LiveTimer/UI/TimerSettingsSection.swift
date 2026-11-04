import SwiftUI

struct TimerSettingsSection: View {
    @Bindable var store: LiveTimerStore
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        if preferences.isOn(.liveTimers) {
            Section {
                Toggle(isOn: $store.playSoundWhenTimeIsUp) {
                    SettingsRowTitle(.notchcastTimers, LocalizedStringResource("Play sound when time is up", table: "Notchcast"))
                }
                Picker(selection: $store.defaultDuration) {
                    ForEach(LiveTimerStore.defaultDurations, id: \.self) { duration in
                        Text(Duration.seconds(duration).formatted(.units(allowed: [.minutes], width: .wide)))
                            .tag(duration)
                    }
                } label: {
                    SettingsRowTitle(.notchcastTimers, LocalizedStringResource("Default timer", table: "Notchcast"))
                }
            } header: {
                SettingsSectionHeader(.notchcastTimers)
            }
            .settingsEnabled(preferences.isOn(.island))
        }
    }
}
