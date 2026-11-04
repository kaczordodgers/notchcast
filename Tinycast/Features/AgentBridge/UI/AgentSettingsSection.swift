import SwiftUI

struct AgentSettingsSection: View {
    let module: AgentCLIModule

    var body: some View {
        Section {
            LabeledContent("Command line tool") {
                Text(status)
                Button("Install") { module.installer.install() }
            }
            Text(module.installer.link.path)
                .textSelection(.enabled)
        } header: {
            Text("Agent access")
        }
        .settingsEnabled(NotchcastPreferences.shared.isOn(.agentActions)
                         && NotchcastPreferences.shared.isOn(.agentCLI))
        .onAppear { module.installer.refresh() }
    }

    private var status: String {
        if module.hasFailed { return String(localized: "Unavailable") }
        switch module.installer.state {
        case .installed: return String(localized: "Installed")
        case .notInstalled: return String(localized: "Not installed")
        case .failed: return String(localized: "Unable to install the command line tool.")
        }
    }
}
