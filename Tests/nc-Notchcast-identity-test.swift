// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift
import Foundation

enum AppPaths {
    static func applicationSupport() -> URL { URL.applicationSupportDirectory.appending(path: "unused") }
}

@main
struct NotchcastIdentityTest {
    static func main() {
        let debug = NotchcastIdentity(bundleIdentifier: "app.notchcast.dev")
        let release = NotchcastIdentity(bundleIdentifier: "app.notchcast")
        assert(debug.suiteName() == "app.notchcast.dev.notchcast")
        assert(release.suiteName() == "app.notchcast.notchcast")
        assert(debug.bundleID == "app.notchcast.dev")
        assert(release.bundleID == "app.notchcast")
        for identity in [debug, release] {
            assert(identity.suiteName(suffix: ".editor") == identity.bundleID + ".editor")
            assert(identity.suiteName(suffix: ".mach-link") == identity.bundleID + ".mach-link")
            assert(identity.suiteName(suffix: ".urlCleaner") == identity.bundleID + ".urlCleaner")
            assert(identity.suiteName(suffix: ".notchcast.agent-consent") == identity.bundleID + ".notchcast.agent-consent")
        }
        let missing = NotchcastIdentity(bundleIdentifier: nil)
        assert(missing.bundleID == "app.notchcast.dev")
        assert(missing.suiteName() == "app.notchcast.dev.notchcast")
        assert(NotchcastIdentity.releaseBundleIdentifier == "app.notchcast")
        assert(NotchcastIdentity.upstreamSubsystem == "com.tinycast")
        let configuration = NotchcastIdentity.sessionConfiguration()
        assert(configuration.urlCache == nil)
        assert(configuration.urlCredentialStorage !== URLCredentialStorage.shared)
        assert(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
        print("PASS identity preserves Debug/Release suites, bundle fallback and private sessions")
    }
}
