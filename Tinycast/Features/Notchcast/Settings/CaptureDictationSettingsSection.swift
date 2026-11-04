import SwiftUI

struct CaptureDictationSettingsSection: View {
    var body: some View {
        Section {
            ColorPickerSettingsSection(module: NotchcastCore.colorPicker)
            ScreenshotSettingsSection(module: NotchcastCore.screenshot)
            ScreenTextSettingsSection(module: NotchcastCore.screenText)
            ScrollingCaptureSettingsSection()
        } header: {
            SettingsSectionHeader(.notchcastCaptureAndDictation)
        }
    }
}
