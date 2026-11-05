import SwiftUI
import UniformTypeIdentifiers

struct ExcludedBundleIDsSettingRow: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        TextField(text: Binding(
            get: { preferences.greenMaximizeExcludedApps },
            set: { preferences.greenMaximizeExcludedApps = $0 })) {
            SettingsRowTitle(.notchcastSystem, LocalizedStringResource("Excluded app bundle IDs (comma-separated)", table: "Notchcast"))
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct QuitProtectionModeSettingRow: View {
    @Bindable var store: QuitProtectionStore

    var body: some View {
        Picker(selection: $store.configuration.mode) {
            Text("Holding ⌘Q", tableName: "Notchcast").tag(QuitProtectionEngine.Mode.hold)
            Text("Pressing ⌘Q twice", tableName: "Notchcast").tag(QuitProtectionEngine.Mode.doublePress)
        } label: {
            SettingsRowTitle(.notchcastQuitProtection, LocalizedStringResource("Confirm by", table: "Notchcast"))
        }
    }
}

struct QuitProtectionCloseSettingRow: View {
    @Bindable var store: QuitProtectionStore

    var body: some View {
        Toggle(isOn: $store.configuration.closeEnabled) {
            SettingsRowTitle(.notchcastQuitProtection, LocalizedStringResource("Protect ⌘W", table: "Notchcast"))
            Text("Same confirmation before closing a window.", tableName: "Notchcast")
        }
    }
}

struct QuitProtectionExceptionsSettingRow: View {
    @Bindable var store: QuitProtectionStore

    var body: some View {
        Text("These apps quit and close without asking.", tableName: "Notchcast")
        if store.configuration.exceptions.isEmpty {
            Text("Nothing here yet.").foregroundStyle(.secondary)
        }
        ForEach(store.configuration.exceptions.sorted(), id: \.self) { identifier in
            QuitProtectionExceptionRow(identifier: identifier) {
                store.configuration.exceptions.remove(identifier)
            }
        }
    }
}

struct QuitProtectionAddAppSettingRow: View {
    private let addApp: LocalizedStringResource = LocalizedStringResource("Add App…", table: "Notchcast")
    @Bindable var store: QuitProtectionStore

    var body: some View {
        Button(action: addApplications) { Text(addApp) }
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

struct DisplayBrightnessSettingRow: View {
    let controller: BrightnessController

    var body: some View {
        if controller.currentDisplays.isEmpty {
            Text("No display can be controlled.", tableName: "Notchcast").foregroundStyle(.secondary)
        }
        ForEach(controller.currentDisplays) { display in
            BrightnessDisplayRow(display: display, controller: controller)
        }
    }
}
