import SwiftUI

struct AgentChatToolsSettingsSection: View {
    @Environment(AppCore.self) private var core
    @Bindable var module: AgentChatToolsModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.agentChatTools) },
            set: { preferences.set(.agentChatTools, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "AI Chat Tools")
                Text(NotchcastFeature.agentChatTools.subtitle)
            }
        LabeledContent {
            if module.isAdded {
                Button("Remove", action: module.remove)
            } else {
                Button("Add Notchcast to AI chat") {
                    if module.add() == .binaryMissing {
                        core.showMessage(String(localized: "Install the Notchcast CLI first."), tone: .danger)
                    }
                }
                .disabled(!module.isRunning)
            }
        } label: {
            Text(module.isAdded
                 ? (core.mcpCoordinator.isActive ? String(localized: "Added") : String(localized: "Disabled"))
                 : String(localized: "Not added"))
        }
    }
}
