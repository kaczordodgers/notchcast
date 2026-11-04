import SwiftUI

struct AIUsageSettingsSection: View {
    let link: AIUsageLinkModule
    @Bindable private var preferences = NotchcastPreferences.shared
    @State private var code = ""
    @State private var failed = false

    var body: some View {
        Section {
            TextField("AI usage cache directory", text: $preferences.aiUsageCachePath)
            LabeledContent("Status", value: link.isPaired
                ? String(localized: "Paired") : String(localized: "Not connected"))
            RevealableSecureField(title: String(localized: "Pairing code"), text: $code)
            Button(link.isPaired ? String(localized: "Unpair") : String(localized: "Pair")) {
                do {
                    if link.isPaired {
                        try link.unpair()
                        code = ""
                    } else {
                        code = try link.pair(code: code)
                    }
                    failed = false
                } catch { failed = true }
            }
            if failed || link.failed { Text("Pairing failed.").foregroundStyle(.secondary) }
        } header: {
            SettingsSectionHeader(.notchcastAIUsage)
        } footer: {
            Text("Pair with an empty code to create one, then enter it on the other Mac.")
        }
        .settingsEnabled(link.isRunning)
    }
}
