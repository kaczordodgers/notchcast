import SwiftUI

struct AgentAnswerSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.agentAnswer) },
            set: { preferences.set(.agentAnswer, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Agent Answers", table: "Notchcast"))
                Text(NotchcastFeature.agentAnswer.subtitle)
            }
    }
}
