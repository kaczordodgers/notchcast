import AppKit
import UniformTypeIdentifiers

@MainActor
enum EditorOpenPanel {
    static func selectFile() -> URL? {
        let preferences = NotchcastPreferences.shared
        guard preferences.isOn(.plainTextFiles) || preferences.isOn(.markdownFiles) else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var extensions: [String] = []
        if preferences.isOn(.plainTextFiles) { extensions += ["txt", "text"] }
        if preferences.isOn(.markdownFiles) { extensions += ["md", "markdown"] }
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
