import Foundation

extension AppearanceCoordinator {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "theme", name: String(localized: "Theme", table: "Notchcast"), sfSymbol: "paintpalette", feature: .appearance,
        legacyID: "command:theme", keepsPalette: true,
        isEnabled: { NotchcastHost.current.appearanceEnabled() },
        run: { NotchcastHost.current.showThemes() })
}
