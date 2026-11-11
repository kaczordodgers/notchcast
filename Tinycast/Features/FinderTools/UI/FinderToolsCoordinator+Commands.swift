import Foundation

extension FinderToolsCoordinator {
    nonisolated static let cutCommand = NotchcastCommand(
        slug: "finder-cut", name: String(localized: "Cut and Move Files", table: "Notchcast"), sfSymbol: "scissors", feature: .finderCutPaste,
        isEnabled: { NotchcastPreferences.shared.isOn(.finderCutPaste) },
        run: { FinderToolsCoordinator.shared.cut() })
    nonisolated static let pasteCommand = NotchcastCommand(
        slug: "finder-paste", name: String(localized: "Paste in Finder", table: "Notchcast"), sfSymbol: "doc.on.clipboard", feature: .finderCutPaste,
        isEnabled: { NotchcastPreferences.shared.isOn(.finderCutPaste) },
        run: { FinderToolsCoordinator.shared.paste() })
    nonisolated static let renameCommand = NotchcastCommand(
        slug: "finder-rename", name: String(localized: "Rename Selection", table: "Notchcast"), sfSymbol: "pencil", feature: .finderRename,
        isEnabled: { NotchcastPreferences.shared.isOn(.finderRename) },
        run: { FinderToolsCoordinator.shared.rename() })
}
