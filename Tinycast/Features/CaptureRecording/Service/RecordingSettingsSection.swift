import SwiftUI

struct RecordingSettingsSection: View {
    @Bindable var module: RecordingModule
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.recording) },
            set: { preferences.set(.recording, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Screen Recording")
                Text(NotchcastFeature.recording.subtitle)
            }
        LabeledContent {
            HStack {
                Picker("Recording frame rate", selection: $module.frameRate) {
                    Text(verbatim: "30 fps").tag(30)
                    Text(verbatim: "60 fps").tag(60)
                }
                Button("Choose…", action: chooseFolder)
                    .accessibilityLabel("Recording folder")
            }
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Recording folder")
            Text(module.folder.path(percentEncoded: false))
        }
        .settingsEnabled(preferences.isOn(.recording))
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
