import Foundation

extension QuitProtectionModule {
    nonisolated static let settingsCommand = NotchcastCommand(
        slug: "quit-protection", name: String(localized: "Quit Protection"), sfSymbol: "hand.raised",
        isEnabled: { NotchcastPreferences.shared.isOn(.quitProtection) },
        run: { AppCore.shared.settingsCoordinator.showSettings(tab: .notchcast) })
}
