import Foundation

struct NotchcastIdentity: Sendable {
    static let fallbackBundleIdentifier = "app.notchcast.dev"
    static let releaseBundleIdentifier = "app.notchcast"
    static let upstreamBundleIdentifier = "com.tinycast.app"
    static let upstreamSubsystem = "com.tinycast"
    static let displayName = "Notchcast"

    static var current: Self { Self(bundleIdentifier: Bundle.main.bundleIdentifier) }
    static var supportRoot: URL { current.standardApplicationSupport }
    static var releaseFallbackSubsystem: String { current.loggerSubsystem(fallback: releaseBundleIdentifier) }
    static var upstreamFallbackSubsystem: String { current.loggerSubsystem(fallback: upstreamBundleIdentifier) }
    static var displayNameFallbackSubsystem: String { current.loggerSubsystem(fallback: displayName) }

    let bundleIdentifier: String?

    var bundleID: String { bundleIdentifier ?? Self.fallbackBundleIdentifier }

    func suiteName(suffix: String = ".notchcast", fallback: String = fallbackBundleIdentifier) -> String {
        (bundleIdentifier ?? fallback) + suffix
    }

    var defaults: UserDefaults { UserDefaults(suiteName: suiteName())! }

    func loggerSubsystem(fallback: String = fallbackBundleIdentifier) -> String {
        bundleIdentifier ?? fallback
    }

    func applicationSupport(fallback: String = fallbackBundleIdentifier) -> URL {
        AppPaths.applicationSupport(bundleID: bundleIdentifier ?? fallback)
    }

    var standardApplicationSupport: URL {
        applicationSupport(fallback: Self.upstreamBundleIdentifier)
    }

    var dayApplicationSupport: URL {
        let directory = bundleID == Self.releaseBundleIdentifier ? Self.displayName : Self.displayName + "-" + bundleID
        return AppPaths.applicationSupport(bundleID: directory)
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return configuration
    }
}
