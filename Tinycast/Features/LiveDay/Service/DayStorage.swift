import Foundation

@MainActor
enum DayStorage {
    static var defaults: UserDefaults {
        NotchcastIdentity.current.defaults
    }

    static var weatherCacheURL: URL {
        let identifier = NotchcastIdentity.current.bundleID
        let directory = identifier == NotchcastIdentity.releaseBundleIdentifier ? "Notchcast" : "Notchcast-" + identifier
        return URL.applicationSupportDirectory.appending(path: directory).appending(path: "weather.json")
    }
}
