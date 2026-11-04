import SwiftUI

struct CaptureDictationSettingsSection: View {
    var body: some View {
        Section {
            ColorPickerSettingsSection(module: NotchcastCore.colorPicker)
            ScreenshotSettingsSection(module: NotchcastCore.screenshot)
            DictationEnglishSettingsSection()
        } header: {
            SettingsSectionHeader(.notchcastCaptureAndDictation)
        }
    }
}
