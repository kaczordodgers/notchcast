import SwiftUI

struct NotchcastMusicSettings: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            NotchcastFeatureToggle(feature: .musicNowPlaying, anchor: .notchcastMusic)
            NotchcastFeatureToggle(feature: .musicLastPlayer, anchor: .notchcastMusic)
                .settingsEnabled(preferences.isOn(.musicNowPlaying))
            NotchcastFeatureToggle(feature: .musicBlockAppleMusic, anchor: .notchcastMusic)
        } header: { SettingsSectionHeader(.notchcastMusic) }
            .settingsEnabled(preferences.isOn(.island))
        if NotchcastCore.services != nil {
            SpotifySettingsSection()
            MicrophoneSettingsSection()
        }
    }
}
