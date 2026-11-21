import SwiftUI

struct ScreenshotsSettingsView: View {
    @AppStorage private var destination: ScreenshotDestination
    @AppStorage private var folder: String?
    @AppStorage private var editAfterCapture: Bool
    private static let anchor = NotchcastSettingsSearch.anchor(.capture)

    init(defaults: UserDefaults) {
        _destination = AppStorage(wrappedValue: .clipboard, ScreenshotBackupKeys.destination, store: defaults)
        _folder = AppStorage(ScreenshotBackupKeys.folder, store: defaults)
        _editAfterCapture = AppStorage(wrappedValue: false, ScreenshotsModule.editAfterCaptureKey, store: defaults)
    }

    var body: some View {
        Toggle(isOn: $editAfterCapture) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Edit after capture", table: "NotchcastScreenshots"))
            Text("Open each new screenshot in the editor before it is copied or saved.",
                 tableName: "NotchcastScreenshots")
        }
        Picker(selection: $destination) {
            Text("Clipboard", tableName: "NotchcastScreenshots").tag(ScreenshotDestination.clipboard)
            Text("File", tableName: "NotchcastScreenshots").tag(ScreenshotDestination.file)
            Text("Clipboard and file", tableName: "NotchcastScreenshots").tag(ScreenshotDestination.both)
        } label: {
            SettingsRowTitle(
                Self.anchor, LocalizedStringResource("Screenshot destination", table: "NotchcastScreenshots"))
        }
        LabeledContent {
            Button(action: chooseFolder) {
                Text("Choose…", tableName: "NotchcastScreenshots")
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Screenshot folder", table: "NotchcastScreenshots"))
            if let folder {
                Text(folder)
            } else {
                Text("Downloads", tableName: "NotchcastScreenshots")
            }
        }
        .settingsEnabled(destination != .clipboard || editAfterCapture)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path(percentEncoded: false)
    }
}
