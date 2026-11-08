// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift Tinycast/Platform/AppPaths.swift
import Foundation

@main
struct NotchcastIdentityTest {
    static func main() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path
        let debug = NotchcastIdentity(bundleIdentifier: "app.notchcast.dev")
        let release = NotchcastIdentity(bundleIdentifier: "app.notchcast")
        assert(debug.suiteName() == "app.notchcast.dev.notchcast")
        assert(release.suiteName() == "app.notchcast.notchcast")
        assert(debug.applicationSupport().path == support + "/app.notchcast.dev")
        assert(release.applicationSupport().path == support + "/app.notchcast")
        assert(debug.dayApplicationSupport.path == support + "/Notchcast-app.notchcast.dev")
        assert(release.dayApplicationSupport.path == support + "/Notchcast")
        for identity in [debug, release] {
            assert(identity.loggerSubsystem() == identity.bundleIdentifier!)
            assert(identity.loggerSubsystem(fallback: "Notchcast") == identity.bundleIdentifier!)
            assert(identity.loggerSubsystem(fallback: "app.notchcast") == identity.bundleIdentifier!)
            assert(identity.loggerSubsystem(fallback: "com.tinycast.app") == identity.bundleIdentifier!)
            assert(identity.suiteName(suffix: ".editor") == identity.bundleID + ".editor")
            assert(identity.suiteName(suffix: ".mach-link") == identity.bundleID + ".mach-link")
            assert(identity.suiteName(suffix: ".urlCleaner", fallback: "app.notchcast") == identity.bundleID + ".urlCleaner")
            assert(identity.suiteName(suffix: ".notchcast.agent-consent") == identity.bundleID + ".notchcast.agent-consent")
        }
        let missing = NotchcastIdentity(bundleIdentifier: nil)
        assert(missing.bundleID == "app.notchcast.dev")
        assert(missing.suiteName() == "app.notchcast.dev.notchcast")
        assert(missing.loggerSubsystem() == "app.notchcast.dev")
        assert(missing.loggerSubsystem(fallback: "app.notchcast") == "app.notchcast")
        assert(missing.loggerSubsystem(fallback: "Notchcast") == "Notchcast")
        assert(missing.suiteName(suffix: ".urlCleaner", fallback: "app.notchcast") == "app.notchcast.urlCleaner")
        assert(NotchcastIdentity.releaseBundleIdentifier == "app.notchcast")
        assert(NotchcastIdentity.upstreamBundleIdentifier == "com.tinycast.app")
        assert(NotchcastIdentity.upstreamSubsystem == "com.tinycast")
        assert(NotchcastIdentity.displayName == "Notchcast")
        let configuration = NotchcastIdentity.sessionConfiguration()
        assert(configuration.urlCache == nil)
        assert(configuration.urlCredentialStorage !== URLCredentialStorage.shared)
        assert(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
        print("PASS identity preserves Debug/Release suites, both storage layouts, logger policies and private sessions")
    }
}
