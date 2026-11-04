import AppKit
import UniformTypeIdentifiers

@MainActor
enum EditorOpenPanel {
    static func selectFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["txt", "text", "md", "markdown"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
