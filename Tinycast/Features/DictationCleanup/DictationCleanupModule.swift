import Foundation
import Observation

@MainActor
@Observable
final class DictationCleanupModule: NotchcastModule {
    private(set) var settings = DictationCleanupSettings()
    var reportFailure: (() -> Void)?
    private let store: DictationCleanupSettingsStore
    private let install: () -> Void
    private let uninstall: () -> Void
    private let readAPIKey: () throws -> String?

    init(store: DictationCleanupSettingsStore, install: @escaping () -> Void,
         uninstall: @escaping () -> Void, readAPIKey: (() throws -> String?)? = nil) {
        self.store = store
        self.install = install
        self.uninstall = uninstall
        self.readAPIKey = readAPIKey ?? store.apiKey
    }

    func load() {
        do { settings = try store.read() } catch { reportFailure?() }
    }

    func start() {
        var updated = settings
        updated.isEnabled = true
        if save(updated) { install() }
    }

    func stop() {
        uninstall()
        var updated = settings
        updated.isEnabled = false
        _ = save(updated)
    }

    @discardableResult
    func save(_ updated: DictationCleanupSettings) -> Bool {
        do {
            try store.save(updated)
            settings = updated
            return true
        } catch {
            reportFailure?()
            return false
        }
    }

    func apiKey() -> String? {
        do { return try readAPIKey() ?? "" } catch { reportFailure?(); return nil }
    }

    func saveAPIKey(_ key: String) {
        do { try store.saveAPIKey(key) } catch { reportFailure?() }
    }
}
