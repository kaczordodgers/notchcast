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
        assert(debug.suiteName(suffix: ".editor") == "app.notchcast.dev.editor")
        assert(debug.suiteName(suffix: ".mach-link") == "app.notchcast.dev.mach-link")
        assert(debug.suiteName(suffix: ".urlCleaner") == "app.notchcast.dev.urlCleaner")
        assert(debug.suiteName(suffix: ".notchcast.agent-consent") == "app.notchcast.dev.notchcast.agent-consent")
        assert(release.suiteName(suffix: ".editor") == "app.notchcast.editor")
        assert(release.suiteName(suffix: ".mach-link") == "app.notchcast.mach-link")
        assert(release.suiteName(suffix: ".urlCleaner") == "app.notchcast.urlCleaner")
        assert(release.suiteName(suffix: ".notchcast.agent-consent") == "app.notchcast.notchcast.agent-consent")
        let missing = NotchcastIdentity(bundleIdentifier: nil)
        assert(missing.bundleID == "app.notchcast.dev")
        assert(missing.suiteName() == "app.notchcast.dev.notchcast")
        let configuration = NotchcastIdentity.sessionConfiguration()
        assert(configuration.urlCache == nil)
        assert(configuration.urlCredentialStorage !== URLCredentialStorage.shared)
        assert(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
        print("PASS identity preserves Debug/Release suites, bundle fallback and private sessions")
    }
}
