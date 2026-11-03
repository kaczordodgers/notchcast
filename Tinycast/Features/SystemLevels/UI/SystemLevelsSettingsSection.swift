import SwiftUI

struct SystemLevelsSettingsSection: View {
    @Bindable var preferences: SystemLevelsPreferences
    private let switches = NotchcastPreferences.shared

    var body: some View {
        Section {
            NotchcastFeatureToggle(feature: .volumeLevels, anchor: .notchcastLevels,
                                  title: "Volume in the island", subtitle: "Replaces the macOS volume overlay.")
            if switches.isOn(.volumeLevels) {
                Toggle(isOn: $preferences.microphone) {
                    SettingsRowTitle(.notchcastLevels, "Microphone mute in the island")
                    Text("Shows when the microphone is muted or unmuted.")
                }
            }
        } header: {
            SettingsSectionHeader(.notchcastLevels)
        }
        .settingsEnabled(switches.isOn(.island))
    }
}
