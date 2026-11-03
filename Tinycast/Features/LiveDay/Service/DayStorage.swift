import Foundation

@MainActor
enum DayStorage {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!
    }

    static var weatherCacheURL: URL {
        let identifier = Bundle.main.bundleIdentifier ?? "app.notchcast.dev"
        let directory = identifier == "app.notchcast" ? "Notchcast" : "Notchcast-" + identifier
        return URL.applicationSupportDirectory.appendingPathComponent(directory)
            .appendingPathComponent("weather.json")
    }
}
