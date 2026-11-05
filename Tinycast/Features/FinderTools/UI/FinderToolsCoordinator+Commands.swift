import Foundation

extension FinderToolsCoordinator {
    nonisolated static let cutCommand = NotchcastCommand(
        slug: "finder-cut", name: String(localized: "Cut and move files", table: "Notchcast"), sfSymbol: "scissors", feature: .finderCutPaste,
        isEnabled: { NotchcastPreferences.shared.isOn(.finderCutPaste) },
        run: { NotchcastCore.finderTools.cut() })
    nonisolated static let pasteCommand = NotchcastCommand(
        slug: "finder-paste", name: String(localized: "Paste in Finder", table: "Notchcast"), sfSymbol: "doc.on.clipboard", feature: .finderCutPaste,
        isEnabled: { NotchcastPreferences.shared.isOn(.finderCutPaste) },
        run: { NotchcastCore.finderTools.paste() })
    nonisolated static let renameCommand = NotchcastCommand(
        slug: "finder-rename", name: String(localized: "Rename selection", table: "Notchcast"), sfSymbol: "pencil", feature: .finderRename,
        isEnabled: { NotchcastPreferences.shared.isOn(.finderRename) },
        run: { NotchcastCore.finderTools.rename() })
}
