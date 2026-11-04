import SwiftUI

struct CaptureEditorSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.captureEditor) },
            set: { preferences.set(.captureEditor, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Screenshot Editor")
            }
    }
}
