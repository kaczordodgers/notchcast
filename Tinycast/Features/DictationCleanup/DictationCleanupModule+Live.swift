import Foundation

extension DictationCleanupModule {
    static let shared = live()

    static func live() -> DictationCleanupModule {
        let identifier = NotchcastIdentity.current.bundleID
        return DictationCleanupModule(
            store: .live(bundleIdentifier: identifier)!,
            install: { DictationFamily.shared.setCleanup(true) },
            uninstall: { DictationFamily.shared.setCleanup(false) })
    }
}
