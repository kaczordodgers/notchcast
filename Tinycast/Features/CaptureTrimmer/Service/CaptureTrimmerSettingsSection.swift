import SwiftUI

struct CaptureTrimmerSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.captureTrimmer) },
            set: { preferences.set(.captureTrimmer, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Recording Trimmer", table: "Notchcast"))
                Text(NotchcastFeature.captureTrimmer.subtitle)
            }
    }
}
