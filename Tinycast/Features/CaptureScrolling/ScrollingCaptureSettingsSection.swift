import SwiftUI

struct ScrollingCaptureSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.scrollingCapture) },
            set: { preferences.set(.scrollingCapture, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Scrolling Capture", table: "Notchcast"))
                Text(NotchcastFeature.scrollingCapture.subtitle)
            }
    }
}
