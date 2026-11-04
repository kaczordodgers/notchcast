import SwiftUI

struct CaptureDictationSettingsSection: View {
    var body: some View {
        Section {
            ColorPickerSettingsSection(module: NotchcastCore.colorPicker)
        } header: {
            SettingsSectionHeader(.notchcastCaptureAndDictation)
        }
    }
}
