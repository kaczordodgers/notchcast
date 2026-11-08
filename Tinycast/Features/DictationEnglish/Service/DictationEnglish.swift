import Foundation
import os

enum DictationEnglish {
    private static let logger = Logger(subsystem: NotchcastIdentity.releaseBundleIdentifier, category: "DictationEnglish")

    @concurrent
    static func process(
        _ raw: String, language: String?, onFallback: @Sendable () async -> Void = {}
    ) async -> String {
        guard let identifier = Bundle.main.bundleIdentifier,
              let store = DictationCleanupSettingsStore.live(bundleIdentifier: identifier)
        else {
            if !Task.isCancelled { await onFallback() }
            return raw
        }
        do {
            let settings = try store.read()
            let result = await process(raw, language: language, settings: settings,
                                       key: try store.apiKey() ?? "", client: DictationCleanupHTTPClient(),
                                       onFallback: onFallback)
            guard !Task.isCancelled, try store.read() == settings else { return raw }
            return result
        } catch {
            logger.notice("English dictation configuration unavailable; using raw transcript")
            if !Task.isCancelled { await onFallback() }
            return raw
        }
    }

    @concurrent
    static func process(
        _ raw: String, language: String?, settings: DictationCleanupSettings, key: String,
        client: any DictationCleanupClient, timeout: Duration = .seconds(30),
        onFallback: @Sendable () async -> Void = {}
    ) async -> String {
        var enabled = settings
        enabled.isEnabled = true
        return await DictationCleanup.process(
            raw, language: language, settings: enabled, key: key, client: client, timeout: timeout,
            systemPrompt: DictationEnglishPrompt.system(settings: settings, language: language),
            onFallback: onFallback)
    }
}
