import SwiftUI

struct CaptureDictationSettingsSection: View {
    var body: some View {
        Section {
            ColorPickerSettingsSection(module: NotchcastCore.colorPicker)
            ScreenshotSettingsSection(module: NotchcastCore.screenshot)
            RecordingSettingsSection(module: NotchcastCore.recording)
        } header: {
            SettingsSectionHeader(.notchcastCaptureAndDictation)
        }
    }
}
