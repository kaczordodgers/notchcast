import SwiftUI
import UniformTypeIdentifiers

struct QuitProtectionSettingsSection: View {
    private let addApp: LocalizedStringResource = "Add App…"
    @Bindable var store: QuitProtectionStore
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        if preferences.isOn(.quitProtection) {
            Section {
                Picker(selection: $store.configuration.mode) {
                    Text("Holding ⌘Q").tag(QuitProtectionEngine.Mode.hold)
                    Text("Pressing ⌘Q twice").tag(QuitProtectionEngine.Mode.doublePress)
                } label: {
                    SettingsRowTitle(.notchcastQuitProtection, "Confirm by")
                }
                Toggle(isOn: $store.configuration.closeEnabled) {
                    SettingsRowTitle(.notchcastQuitProtection, "Protect ⌘W")
                    Text("Same confirmation before closing a window.")
                }
                if store.configuration.exceptions.isEmpty {
                    Text("Nothing here yet.").foregroundStyle(.secondary)
                }
                ForEach(store.configuration.exceptions.sorted(), id: \.self) { identifier in
                    QuitProtectionExceptionRow(identifier: identifier) {
                        store.configuration.exceptions.remove(identifier)
                    }
                }
                Button(action: addApplications) { Text(addApp) }
            } header: {
                SettingsSectionHeader(.notchcastQuitProtection)
            } footer: {
                Text("These apps quit and close without asking.")
            }
        }
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let identifier = Bundle(url: url)?.bundleIdentifier {
                store.configuration.exceptions.insert(identifier)
            }
        }
    }
}
