import Foundation

enum DayCommands {
    static let weather = NotchcastCommand(
        slug: "weather", name: String(localized: "Weather"), sfSymbol: "cloud.sun",
        isEnabled: { IslandController.shared.commandsAvailable && NotchcastPreferences.shared.isOn(.dayWeather) },
        run: { IslandController.shared.open(page: .day) })

    static let markets = NotchcastCommand(
        slug: "markets", name: String(localized: "Markets"), sfSymbol: "chart.line.uptrend.xyaxis",
        isEnabled: { IslandController.shared.commandsAvailable && NotchcastPreferences.shared.isOn(.dayMarkets) },
        run: { IslandController.shared.open(page: .day) })

    static let calendar = NotchcastCommand(
        slug: "open-day", name: String(localized: "Open Day"), sfSymbol: "calendar",
        isEnabled: { IslandController.shared.commandsAvailable && AppCore.shared.settings.calendarEnabled },
        run: { IslandController.shared.open(page: .day) })
}
