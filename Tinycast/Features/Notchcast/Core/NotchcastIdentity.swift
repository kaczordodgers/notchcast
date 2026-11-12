import Foundation

struct NotchcastIdentity: Sendable {
    static let fallbackBundleIdentifier = "app.notchcast.dev"
    static let releaseBundleIdentifier = "app.notchcast"

    static var current: Self { Self(bundleIdentifier: Bundle.main.bundleIdentifier) }
    static var supportRoot: URL { AppPaths.applicationSupport() }

    let bundleIdentifier: String?

    var bundleID: String { bundleIdentifier ?? Self.fallbackBundleIdentifier }

    func suiteName(suffix: String = ".notchcast") -> String { bundleID + suffix }

    var defaults: UserDefaults { UserDefaults(suiteName: suiteName())! }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return configuration
    }
}
