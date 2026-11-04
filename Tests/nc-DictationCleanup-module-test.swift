// notchcast-sources: Tinycast/Features/DictationCleanup/DictationCleanupModule*.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Model/DictationCleanupSettings.swift

import Foundation

@MainActor protocol NotchcastModule { func start(); func stop() }
@MainActor final class DictationCleanupSettingsStore {
    enum Failure: Error { case unavailable }
    var settings = DictationCleanupSettings()
    var fails = false
    static func live(bundleIdentifier: String) -> DictationCleanupSettingsStore? { .init() }
    func read() throws -> DictationCleanupSettings {
        if fails { throw Failure.unavailable }
        return settings
    }
    func save(_ value: DictationCleanupSettings) throws {
        if fails { throw Failure.unavailable }
        settings = value
    }
    func apiKey() throws -> String? {
        if fails { throw Failure.unavailable }
        return "fake"
    }
    func saveAPIKey(_ value: String) throws {
        if fails { throw Failure.unavailable }
    }
}
@MainActor enum DictationCoordinator { static var transcriptStage: (() -> Void)? }
@MainActor enum DictationCleanup {
    static var installs = 0
    static func install() { installs += 1; DictationCoordinator.transcriptStage = {} }
    static func uninstall() { DictationCoordinator.transcriptStage = nil }
}

@main struct CleanupModuleTest {
    @MainActor static func main() {
        let store = DictationCleanupSettingsStore()
        var installs = 0
        var stops = 0
        var failures = 0
        let module = DictationCleanupModule(store: store, install: { installs += 1 },
                                            uninstall: { stops += 1 })
        module.reportFailure = { failures += 1 }
        module.load()
        module.start()
        precondition(installs == 1 && module.settings.isEnabled && store.settings.isEnabled)
        module.stop()
        precondition(stops == 1 && !module.settings.isEnabled && !store.settings.isEnabled)
        precondition(module.apiKey() == "fake")
        store.fails = true
        module.start()
        precondition(installs == 1 && !module.settings.isEnabled && failures == 1)
        module.load()
        precondition(module.apiKey() == nil)
        module.saveAPIKey("test")
        precondition(failures == 4)
        module.stop()
        precondition(stops == 2 && failures == 5)
        let live = DictationCleanupModule.live()
        live.start()
        precondition(DictationCleanup.installs == 1 && DictationCoordinator.transcriptStage != nil)
        live.stop()
        precondition(DictationCoordinator.transcriptStage == nil)
        print("PASS cleanup module lifecycle, persistence failures and live installation wiring")
    }
}
