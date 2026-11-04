import Foundation

extension PlainPasteModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "paste-plain-text", name: String(localized: "Paste Plain Text"), sfSymbol: "doc.plaintext",
        isEnabled: { NotchcastPreferences.shared.isOn(.pastePlain) },
        run: { NotchcastCore.pastePlain?.paste() })
}
