import Foundation

extension AppearanceCoordinator {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "theme", name: String(localized: "Theme"), sfSymbol: "paintpalette", feature: .appearance,
        legacyID: "command:theme",
        isEnabled: { AppCore.shared.appearanceCoordinator.isEnabled },
        run: { AppCore.shared.appearanceCoordinator.showThemes() })
}
