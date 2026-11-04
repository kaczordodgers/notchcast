import Foundation

extension DictationCleanupModule {
    static func live() -> DictationCleanupModule {
        let identifier = Bundle.main.bundleIdentifier ?? "app.notchcast.dev"
        return DictationCleanupModule(
            store: .live(bundleIdentifier: identifier)!,
            install: { DictationCleanup.install() },
            uninstall: { DictationCleanup.uninstall() })
    }
}
