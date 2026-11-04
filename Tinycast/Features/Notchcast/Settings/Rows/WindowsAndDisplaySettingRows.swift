import SwiftUI
import UniformTypeIdentifiers

struct ExcludedBundleIDsSettingRow: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        TextField(text: Binding(
            get: { preferences.greenMaximizeExcludedApps },
            set: { preferences.greenMaximizeExcludedApps = $0 })) {
            SettingsRowTitle(.notchcastSystem, "Excluded app bundle IDs (comma-separated)")
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct QuitProtectionModeSettingRow: View {
    @Bindable var store: QuitProtectionStore

    var body: some View {
        Picker(selection: $store.configuration.mode) {
            Text("Holding ⌘Q").tag(QuitProtectionEngine.Mode.hold)
            Text("Pressing ⌘Q twice").tag(QuitProtectionEngine.Mode.doublePress)
        } label: {
            SettingsRowTitle(.notchcastQuitProtection, "Confirm by")
        }
    }
}

struct QuitProtectionCloseSettingRow: View {
    @Bindable var store: QuitProtectionStore

    var body: some View {
        Toggle(isOn: $store.configuration.closeEnabled) {
            SettingsRowTitle(.notchcastQuitProtection, "Protect ⌘W")
            Text("Same confirmation before closing a window.")
        }
    }
}

struct QuitProtectionExceptionsSettingRow: View {
    @Bindable var store: QuitProtectionStore

    var body: some View {
        Text("These apps quit and close without asking.")
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
    private let addApp: LocalizedStringResource = "Add App…"
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
            Text("No display can be controlled.").foregroundStyle(.secondary)
        }
        ForEach(controller.currentDisplays) { display in
            BrightnessDisplayRow(display: display, controller: controller)
        }
    }
}
