import Foundation

extension PlainPasteModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "paste-plain-text", name: String(localized: "Paste Plain Text", table: "Notchcast"), sfSymbol: "doc.plaintext", feature: .pastePlain,
        run: { PlainPasteModule.shared.paste() })
}
