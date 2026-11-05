import SwiftUI

struct ScreenshotDestinationSettingRow: View {
    @Bindable var module: ScreenshotModule

    var body: some View {
        Picker(selection: $module.destination) {
            Text("Clipboard").tag(ScreenshotModule.Destination.clipboard)
            Text("File").tag(ScreenshotModule.Destination.file)
            Text("Clipboard and file", tableName: "Notchcast").tag(ScreenshotModule.Destination.both)
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Screenshot destination", table: "Notchcast"))
        }
    }
}

struct ScreenshotFolderSettingRow: View {
    @Bindable var module: ScreenshotModule

    var body: some View {
        LabeledContent {
            Button("Choose…", action: chooseFolder)
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Screenshot folder", table: "Notchcast"))
            if let folder = module.folder {
                Text(folder.path(percentEncoded: false))
            } else {
                Text("Desktop", tableName: "Notchcast")
            }
        }
        .settingsEnabled(module.destination != .clipboard)
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

struct ScreenTextLineBreaksSettingRow: View {
    @Bindable var module: ScreenTextModule

    var body: some View {
        Toggle(isOn: $module.removeLineBreaks) {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Remove line breaks", table: "Notchcast"))
        }
    }
}

struct ColorFormatSettingRow: View {
    @Bindable var module: ColorPickerModule

    var body: some View {
        Picker(selection: $module.format) {
            Text(verbatim: "#RRGGBB").tag(ColorPickerFormat.hex)
            Text(verbatim: "#rrggbb").tag(ColorPickerFormat.hexLowercase)
            Text(verbatim: "rgb()").tag(ColorPickerFormat.rgb)
            Text(verbatim: "hsl()").tag(ColorPickerFormat.hsl)
            Text(verbatim: "SwiftUI Color").tag(ColorPickerFormat.swiftUIColor)
            Text(verbatim: "NSColor #colorLiteral").tag(ColorPickerFormat.nsColorLiteral)
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Color format", table: "Notchcast"))
        }
    }
}

struct RecordingFolderSettingRow: View {
    @Bindable var module: RecordingModule

    var body: some View {
        LabeledContent {
            HStack {
                RecordingFrameRateSettingRow(module: module)
                Button("Choose…", action: chooseFolder)
                    .accessibilityLabel(String(localized: "Recording folder", table: "Notchcast"))
            }
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Recording folder", table: "Notchcast"))
            Text(module.folder.path(percentEncoded: false))
        }
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

struct RecordingFrameRateSettingRow: View {
    @Bindable var module: RecordingModule

    var body: some View {
        Picker(String(localized: "Recording frame rate", table: "Notchcast"), selection: $module.frameRate) {
            Text(verbatim: "30 fps").tag(30)
            Text(verbatim: "60 fps").tag(60)
        }
    }
}
