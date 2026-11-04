import Foundation

extension IslandPage {
    var launcherCommand: NotchcastCommand {
        let slug: String
        let name: String
        switch self {
        case .home:
            slug = "island-home"
            name = String(localized: "Show Island Home")
        case .day:
            slug = "island-day"
            name = String(localized: "Show Island Day")
        }
        return NotchcastCommand(
            slug: slug, name: name, sfSymbol: symbol,
            isEnabled: {
                let preferences = NotchcastPreferences.shared
                guard IslandController.shared.commandsAvailable, preferences.isOn(.island) else { return false }
                switch self {
                case .home: return true
                case .day: return preferences.isOn(.dayWeather) || preferences.isOn(.dayMarkets)
                }
            }, run: {
                let island = IslandController.shared
                island.open(page: self, takeKey: true)
                island.selectPage(self)
            })
    }
}
