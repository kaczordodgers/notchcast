import AppKit
import UniformTypeIdentifiers

@MainActor
enum EditorOpenPanel {
    static func selectFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let preferences = NotchcastPreferences.shared
        var extensions: [String] = []
        if preferences.isOn(.plainTextFiles) { extensions += ["txt", "text"] }
        if preferences.isOn(.markdownFiles) { extensions += ["md", "markdown"] }
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
