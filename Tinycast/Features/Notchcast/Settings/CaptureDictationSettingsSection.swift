import SwiftUI

struct CaptureDictationSettingsSection: View {
    var body: some View {
        Section {
            ColorPickerSettingsSection(module: NotchcastCore.colorPicker)
            ScreenshotSettingsSection(module: NotchcastCore.screenshot)
            DictationCleanupSettingsSection(module: NotchcastCore.dictationCleanup)
        } header: {
            SettingsSectionHeader(.notchcastCaptureAndDictation)
        }
    }
}
