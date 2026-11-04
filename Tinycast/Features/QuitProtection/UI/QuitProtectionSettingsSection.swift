import SwiftUI
import UniformTypeIdentifiers

struct QuitProtectionSettingsSection: View {
    private let addApp: LocalizedStringResource = LocalizedStringResource("Add App…", table: "Notchcast")
    @Bindable var store: QuitProtectionStore
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        if preferences.isOn(.quitProtection) {
            Section {
                Picker(selection: $store.configuration.mode) {
                    Text("Holding ⌘Q", tableName: "Notchcast").tag(QuitProtectionEngine.Mode.hold)
                    Text("Pressing ⌘Q twice", tableName: "Notchcast").tag(QuitProtectionEngine.Mode.doublePress)
                } label: {
                    SettingsRowTitle(.notchcastQuitProtection, LocalizedStringResource("Confirm by", table: "Notchcast"))
                }
                Toggle(isOn: $store.configuration.closeEnabled) {
                    SettingsRowTitle(.notchcastQuitProtection, LocalizedStringResource("Protect ⌘W", table: "Notchcast"))
                    Text("Same confirmation before closing a window.", tableName: "Notchcast")
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
                Text("These apps quit and close without asking.", tableName: "Notchcast")
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
