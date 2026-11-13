import Foundation

extension DictationCleanupModule {
    static let shared = live()

    static func live() -> DictationCleanupModule {
        let identifier = NotchcastIdentity.current.bundleID
        let module = DictationCleanupModule(
            store: .live(bundleIdentifier: identifier)!,
            install: { DictationFamily.shared.setCleanup(true) },
            uninstall: { DictationFamily.shared.setCleanup(false) })
        DictationFamily.shared.cleanupFallback = { [weak module] in module?.fellBack() }
        return module
    }
}
