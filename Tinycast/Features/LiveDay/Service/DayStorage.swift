import Foundation

@MainActor
enum DayStorage {
    static var defaults: UserDefaults {
        NotchcastIdentity.current.defaults
    }

    static var weatherCacheURL: URL {
        NotchcastIdentity.current.dayApplicationSupport
            .appendingPathComponent("weather.json")
    }
}
