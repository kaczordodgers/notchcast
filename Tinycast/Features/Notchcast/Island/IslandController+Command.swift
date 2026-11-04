import Foundation

extension IslandController {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "toggle-island", name: String(localized: "Toggle Island"),
        sfSymbol: "rectangle.topthird.inset.filled", feature: .island, legacyID: "command:toggle-island",
        isEnabled: { shared.commandsAvailable }, run: { shared.toggle() })
}
