import Foundation

extension DictationCleanupModule {
    static func live() -> DictationCleanupModule {
        let identifier = NotchcastIdentity.current.bundleID
        return DictationCleanupModule(
            store: .live(bundleIdentifier: identifier)!,
            install: { DictationCleanup.install() },
            uninstall: { DictationCleanup.uninstall() })
    }
}
