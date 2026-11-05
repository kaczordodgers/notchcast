import Foundation

enum DayCommands {
    static let weather = NotchcastCommand(
        slug: "weather", name: String(localized: "Weather"), sfSymbol: "cloud.sun", feature: .dayWeather,
        isEnabled: { IslandController.shared.commandsAvailable && NotchcastPreferences.shared.isOn(.dayWeather) },
        run: { IslandController.shared.open(page: .day) })

    static let markets = NotchcastCommand(
        slug: "markets", name: String(localized: "Markets", table: "Notchcast"), sfSymbol: "chart.line.uptrend.xyaxis", feature: .dayMarkets,
        isEnabled: { IslandController.shared.commandsAvailable && NotchcastPreferences.shared.isOn(.dayMarkets) },
        run: { IslandController.shared.open(page: .day) })

    static let calendar = NotchcastCommand(
        slug: "open-day", name: String(localized: "Open Day", table: "Notchcast"), sfSymbol: "calendar", feature: .dayCalendar,
        isEnabled: { IslandController.shared.commandsAvailable && NotchcastPreferences.shared.isOn(.dayCalendar) },
        run: { IslandController.shared.open(page: .day) })
}
