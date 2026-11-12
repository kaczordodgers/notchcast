// notchcast-sources: Tinycast/Features/LiveDay/DayCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandPage+Command.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

enum NotchcastFeature: Hashable { case island, dayCalendar, dayWeather, dayMarkets, aiUsage }
enum IslandPage { case home, day, usage
    var symbol: String { "calendar" }
}
@MainActor final class IslandController {
    static let shared = IslandController()
    var commandsAvailable = true
    func open(page: IslandPage, takeKey: Bool = false) {}
    func selectPage(_ page: IslandPage) {}
}

@main @MainActor struct DayCommandTests {
    static func main() {
        let preferences = NotchcastPreferences.shared
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures += 1 }
        }
        preferences.only = [.island, .dayCalendar]
        check(DayCommands.calendar.isEnabled(), "Open Day enabled with fork calendar only")
        check(IslandPage.day.launcherCommand.isEnabled(), "Island Day enabled with fork calendar only")
        preferences.only = [.island]
        check(!IslandPage.day.launcherCommand.isEnabled(), "Island Day disabled with all Day switches off")
        check(!DayCommands.calendar.isEnabled(), "Open Day disabled with calendar off")
        for feature: NotchcastFeature in [.dayWeather, .dayMarkets] {
            preferences.only = [.island, feature]
            check(IslandPage.day.launcherCommand.isEnabled(), "Island Day enabled with \(feature)")
        }
        preferences.only = [.dayCalendar]
        check(!IslandPage.day.launcherCommand.isEnabled(), "Island Day requires island switch")
        preferences.only = [.island]
        check(!IslandPage.usage.launcherCommand.isEnabled(), "AI Usage requires its feature switch")
        preferences.only = [.island, .aiUsage]
        check(IslandPage.usage.launcherCommand.isEnabled(), "AI Usage enabled with its feature switch")
        preferences.only = [.aiUsage]
        check(!IslandPage.usage.launcherCommand.isEnabled(), "AI Usage requires Island")
        preferences.only = [.island, .dayCalendar]
        IslandController.shared.commandsAvailable = false
        check(!DayCommands.calendar.isEnabled(), "Open Day requires commandsAvailable")
        check(!IslandPage.day.launcherCommand.isEnabled(), "Island Day requires commandsAvailable")
        exit(failures == 0 ? 0 : 1)
    }
}
