import SwiftUI

struct ScreenshotSettingsSection: View {
    @Bindable var module: ScreenshotModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.screenshot) },
            set: { preferences.set(.screenshot, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Screenshots")
                Text(NotchcastFeature.screenshot.subtitle)
            }
        Picker(selection: $module.destination) {
            Text("Clipboard").tag(ScreenshotModule.Destination.clipboard)
            Text("File").tag(ScreenshotModule.Destination.file)
            Text("Clipboard and file").tag(ScreenshotModule.Destination.both)
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Screenshot destination")
        }
        .settingsEnabled(preferences.isOn(.screenshot))
        LabeledContent {
            Button("Choose…", action: chooseFolder)
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Screenshot folder")
            if let folder = module.folder {
                Text(folder.path(percentEncoded: false))
            } else {
                Text("Desktop")
            }
        }
        .settingsEnabled(preferences.isOn(.screenshot) && module.destination != .clipboard)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = module.folder
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        module.folder = folder
    }
}
