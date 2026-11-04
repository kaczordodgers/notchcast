import Foundation

extension IslandController {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "toggle-island", name: String(localized: "Toggle Island", table: "Notchcast"),
        sfSymbol: "rectangle.topthird.inset.filled", legacyID: "command:toggle-island",
        isEnabled: { shared.commandsAvailable }, run: { shared.toggle() })
}
