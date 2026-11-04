import SwiftUI

struct CaptureDictationSettingsSection: View {
    var body: some View {
        Section {
            ColorPickerSettingsSection(module: NotchcastCore.colorPicker)
            ScreenshotSettingsSection(module: NotchcastCore.screenshot)
            DictationEnglishSettingsSection()
            DictationHistorySettingsSection()
            DictationCleanupSettingsSection(module: NotchcastCore.dictationCleanup)
            CaptureTrimmerSettingsSection()
            AgentAnswerSettingsSection()
            if let module = NotchcastCore.voiceAsk { VoiceAskSettingsSection(module: module) }
            RecordingSettingsSection(module: NotchcastCore.recording)
            ScreenTextSettingsSection(module: NotchcastCore.screenText)
            ScrollingCaptureSettingsSection()
            DictationTriggerSettingsSection()
            AgentMCPSettingsSection()
            if let module = NotchcastCore.agentChatTools { AgentChatToolsSettingsSection(module: module) }
        } header: {
            SettingsSectionHeader(.notchcastCaptureAndDictation)
        }
    }
}
