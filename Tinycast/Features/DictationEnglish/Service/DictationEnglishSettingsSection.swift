import SwiftUI

struct DictationEnglishSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(get: { preferences.isOn(.dictationEnglish) },
                             set: { preferences.set(.dictationEnglish, $0) })) {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Dictate in English", table: "Notchcast"))
        }
    }
}
