import Foundation

enum AppearanceCommands {
    static let settings = NotchcastCommand(
        slug: "appearance", name: String(localized: "Appearance"), sfSymbol: "paintpalette", feature: .appearance,
        run: { AppCore.shared.settingsCoordinator.showSettings(tab: .general) })
}
