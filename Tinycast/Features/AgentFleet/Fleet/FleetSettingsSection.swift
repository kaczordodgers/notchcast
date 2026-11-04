import SwiftUI

struct FleetSettingsSection: View {
    @Bindable var settings: AgentFleetSettings
    @State private var token = ""

    var body: some View {
        Section {
            TextField("Remote environment ID", text: $settings.remoteEnvironmentID)
            TextField("Bot host loopback URL", text: $settings.botURL)
            SecureField("Bot host token", text: $token)
            Button("Save token") {
                do {
                    try KeychainSecretStore(scope: "bot-host").setSecret(token, for: settings.tokenAccount)
                    token = ""
                } catch {
                    IslandActivityCenter.shared.showMessage(error.localizedDescription, tone: .neutral, dwell: 5)
                }
            }
        } header: {
            Text(NotchcastFeature.fleetPanel.title)
        }
    }
}
