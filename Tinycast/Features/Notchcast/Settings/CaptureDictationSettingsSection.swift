import SwiftUI

struct CaptureDictationSettingsSection: View {
    var body: some View {
        Section {
            ColorPickerSettingsSection(module: NotchcastCore.colorPicker)
            ScreenshotSettingsSection(module: NotchcastCore.screenshot)
            if let module = NotchcastCore.voiceAsk { VoiceAskSettingsSection(module: module) }
        } header: {
            SettingsSectionHeader(.notchcastCaptureAndDictation)
        }
    }
}
