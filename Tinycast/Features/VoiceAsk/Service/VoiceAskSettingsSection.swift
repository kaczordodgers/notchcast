import SwiftUI

struct VoiceAskSettingsSection: View {
    @Bindable var module: VoiceAskModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(get: { preferences.isOn(.voiceAsk) },
                             set: { preferences.set(.voiceAsk, $0) })) {
            Text(NotchcastFeature.voiceAsk.title)
        }
        TextField("Voice Ask destination", text: $module.destination)
            .settingsEnabled(preferences.isOn(.voiceAsk))
    }
}
