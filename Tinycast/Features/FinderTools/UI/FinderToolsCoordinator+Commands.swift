import Foundation

extension FinderToolsCoordinator {
    static let cutCommand = NotchcastCommand(
        slug: "finder-cut", name: String(localized: "Cut and move files"), sfSymbol: "scissors",
        isEnabled: { NotchcastPreferences.shared.isOn(.finderCutPaste) },
        run: { NotchcastCore.finderTools.cut() })
    static let pasteCommand = NotchcastCommand(
        slug: "finder-paste", name: String(localized: "Paste in Finder"), sfSymbol: "doc.on.clipboard",
        isEnabled: { NotchcastPreferences.shared.isOn(.finderCutPaste) },
        run: { NotchcastCore.finderTools.paste() })
    static let renameCommand = NotchcastCommand(
        slug: "finder-rename", name: String(localized: "Rename selection"), sfSymbol: "pencil",
        isEnabled: { NotchcastPreferences.shared.isOn(.finderRename) },
        run: { NotchcastCore.finderTools.rename() })
}
