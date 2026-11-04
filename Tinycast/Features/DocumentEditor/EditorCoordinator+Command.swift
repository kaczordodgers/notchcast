import Foundation

extension EditorCoordinator {
    nonisolated static let openCommand = NotchcastCommand(
        slug: "open-file-in-editor", name: String(localized: "Open File in Editor"),
        sfSymbol: "doc.text", isEnabled: { NotchcastCore.editor.isEnabled },
        run: { NotchcastCore.editor.openFile() })
}
