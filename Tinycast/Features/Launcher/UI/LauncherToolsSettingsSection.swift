import SwiftUI

struct LauncherToolsSettingsSection: View {
    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                LabeledContent("GitHub Token") {
                    Text(tokenStatus)
                }
            }
        } header: {
            SettingsSectionHeader(.notchcastLauncherTools)
        }
    }

    private var tokenStatus: String {
        do {
            return try KeychainSecretStore(scope: "github").hasSecret(for: GitHubModule.account)
                ? String(localized: "Configured") : String(localized: "Not configured")
        } catch {
            return String(localized: "Unavailable")
        }
    }
}
