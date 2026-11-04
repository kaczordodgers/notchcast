import SwiftUI

struct ScreenTextSettingsSection: View {
    @Bindable var module: ScreenTextModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.screenText) },
            set: { preferences.set(.screenText, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Capture Text")
                Text(NotchcastFeature.screenText.subtitle)
            }
        Toggle(isOn: $module.removeLineBreaks) {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Remove line breaks")
        }
        .settingsEnabled(preferences.isOn(.screenText))
    }
}
