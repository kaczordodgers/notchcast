import SwiftUI

struct BrightnessSettingsSection: View {
    let controller: BrightnessController
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        if preferences.isOn(.displayBrightness) {
            Section {
                if controller.currentDisplays.isEmpty {
                    Text("No display can be controlled.").foregroundStyle(.secondary)
                }
                ForEach(controller.currentDisplays) { display in
                    BrightnessDisplayRow(display: display, controller: controller)
                }
            } header: {
                SettingsSectionHeader(.notchcastBrightness)
            }
        }
    }
}
