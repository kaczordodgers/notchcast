import Foundation
import os

extension DictationFamily {
    static let shared = DictationFamily(process: { raw, language, english, onFallback in
        await live(raw, language: language, english: english, onFallback: onFallback)
    })

    nonisolated private static let logger = Logger(
        subsystem: NotchcastIdentity.releaseBundleIdentifier, category: "DictationFamily")

    @concurrent
    private static func live(
        _ raw: String, language: String?, english: Bool, onFallback: @Sendable () async -> Void
    ) async -> String {
        guard !Task.isCancelled else { return raw }
        guard let identifier = Bundle.main.bundleIdentifier,
              let store = DictationCleanupSettingsStore.live(bundleIdentifier: identifier)
        else {
            if !Task.isCancelled { await onFallback() }
            return raw
        }
        do {
            let settings = try store.read()
            if !english, !settings.isEnabled { return raw }
            let key = try store.apiKey() ?? ""
            let client = DictationCleanupHTTPClient()
            let result = english
                ? await DictationEnglish.process(raw, language: language, settings: settings, key: key,
                                                 client: client, onFallback: onFallback)
                : await DictationCleanup.process(raw, language: language, settings: settings, key: key,
                                                 client: client)
            guard !Task.isCancelled, try store.read() == settings else { return raw }
            return result
        } catch {
            logger.notice("Dictation configuration unavailable; using raw transcript")
            if !Task.isCancelled { await onFallback() }
            return raw
        }
    }
}
