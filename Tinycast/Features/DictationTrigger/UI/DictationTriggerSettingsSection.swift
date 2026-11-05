import SwiftUI

struct DictationTriggerSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.globeDictation) },
            set: { preferences.set(.globeDictation, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Globe Dictation", table: "Notchcast"))
                Text(NotchcastFeature.globeDictation.subtitle)
            }
    }
}
