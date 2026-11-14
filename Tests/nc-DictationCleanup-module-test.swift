// notchcast-sources: Tinycast/Features/Notchcast/Core/MagpieGateway.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/DictationCleanupModule.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/DictationCleanupModule+Live.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Model/DictationCleanupSettings.swift
// notchcast-sources: Tinycast/Features/Notchcast/Dictation/DictationFamily.swift Tests/dictation-family-stubs.swift

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

@main struct CleanupModuleTest {
    @MainActor static func main() async {
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
        var fallbacks = 0
        live.reportFallback = { fallbacks += 1 }
        DictationFamily.shared.cleanupFallback?()
        DictationFamily.shared.cleanupFallback?()
        precondition(fallbacks == 1, "Cleanup fallback reported more than once")
        live.saveAPIKey("new")
        DictationFamily.shared.cleanupFallback?()
        precondition(fallbacks == 2, "Saving settings did not re-arm the fallback report")
        live.start()
        precondition(DictationCoordinator.transcriptStage != nil)
        DictationFamily.shared.cleanupFallback?()
        precondition(fallbacks == 3, "Starting cleanup did not re-arm the fallback report")
        _ = await DictationCoordinator.transcriptStage?("cleaned", nil)
        DictationFamily.shared.cleanupFallback?()
        precondition(fallbacks == 4, "Successful cleanup did not re-arm the fallback report")
        live.stop()
        precondition(DictationCoordinator.transcriptStage == nil)
        print("PASS cleanup module lifecycle, persistence failures, live installation wiring and fallback report")
    }
}
