// notchcast-sources: Tinycast/Features/LiveDay/DayCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandPage+Command.swift
// notchcast-kit: command
import Foundation

enum NotchcastFeature: Hashable { case island, dayCalendar, dayWeather, dayMarkets }
enum IslandPage { case home, day
    var symbol: String { "calendar" }
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled: Set<NotchcastFeature> = []
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled.contains(feature) }
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
        preferences.enabled = [.island, .dayCalendar]
        check(DayCommands.calendar.isEnabled(), "Open Day enabled with fork calendar only")
        check(IslandPage.day.launcherCommand.isEnabled(), "Island Day enabled with fork calendar only")
        preferences.enabled = [.island]
        check(!IslandPage.day.launcherCommand.isEnabled(), "Island Day disabled with all Day switches off")
        check(!DayCommands.calendar.isEnabled(), "Open Day disabled with calendar off")
        for feature: NotchcastFeature in [.dayWeather, .dayMarkets] {
            preferences.enabled = [.island, feature]
            check(IslandPage.day.launcherCommand.isEnabled(), "Island Day enabled with \(feature)")
        }
        preferences.enabled = [.dayCalendar]
        check(!IslandPage.day.launcherCommand.isEnabled(), "Island Day requires island switch")
        preferences.enabled = [.island, .dayCalendar]
        IslandController.shared.commandsAvailable = false
        check(!DayCommands.calendar.isEnabled(), "Open Day requires commandsAvailable")
        check(!IslandPage.day.launcherCommand.isEnabled(), "Island Day requires commandsAvailable")
        exit(failures == 0 ? 0 : 1)
    }
}
