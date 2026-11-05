import SwiftUI

struct AgentMCPSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.agentMCPServer) },
            set: { preferences.set(.agentMCPServer, $0) }
        )) {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Agent MCP Server", table: "Notchcast"))
            Text(NotchcastFeature.agentMCPServer.subtitle)
        }
    }
}
