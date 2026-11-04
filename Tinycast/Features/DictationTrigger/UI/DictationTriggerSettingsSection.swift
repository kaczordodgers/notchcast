import SwiftUI

struct DictationTriggerSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.globeDictation) },
            set: { preferences.set(.globeDictation, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Globe Dictation")
                Text(NotchcastFeature.globeDictation.subtitle)
            }
    }
}
