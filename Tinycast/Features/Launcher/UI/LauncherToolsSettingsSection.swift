import SwiftUI

struct LauncherToolsSettingsSection: View {
    @State private var token = ""
    @State private var status = String(localized: "Not configured")

    var body: some View {
        Section {
            LabeledContent("GitHub Token") {
                VStack(alignment: .leading) {
                    SecureField("GitHub Token", text: $token)
                        .settingsEditorTextField()
                    HStack {
                        Button("Save") { updateToken(remove: false) }
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove") { updateToken(remove: true) }
                        Text(status)
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.notchcastLauncherTools)
        }
        .task { readStatus() }
    }

    private func updateToken(remove: Bool) {
        do {
            let store = KeychainSecretStore(scope: "github")
            if remove {
                try store.removeSecret(for: GitHubModule.account)
            } else {
                try store.setSecret(token.trimmingCharacters(in: .whitespacesAndNewlines), for: GitHubModule.account)
            }
            token = ""
            readStatus()
        } catch {
            status = String(localized: "Unavailable")
        }
    }

    private func readStatus() {
        do {
            status = try KeychainSecretStore(scope: "github").hasSecret(for: GitHubModule.account)
                ? String(localized: "Configured") : String(localized: "Not configured")
        } catch {
            status = String(localized: "Unavailable")
        }
    }
}
