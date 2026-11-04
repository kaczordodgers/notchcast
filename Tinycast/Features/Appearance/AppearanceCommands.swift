import Foundation

enum AppearanceCommands {
    static let settings = NotchcastCommand(
        slug: "appearance", name: String(localized: "Appearance"), sfSymbol: "paintpalette",
        run: { AppCore.shared.settingsCoordinator.showSettings(tab: .general) })
}
