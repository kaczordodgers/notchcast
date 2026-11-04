import Foundation
import os

enum DictationEnglish {
    private static let logger = Logger(subsystem: "app.notchcast", category: "DictationEnglish")

    @concurrent
    static func process(_ raw: String, language: String?) async -> String {
        guard let identifier = Bundle.main.bundleIdentifier,
              let store = DictationCleanupSettingsStore.live(bundleIdentifier: identifier)
        else { return raw }
        do {
            let settings = try store.read()
            let result = await process(raw, language: language, settings: settings,
                                       key: try store.apiKey() ?? "", client: DictationCleanupHTTPClient())
            guard !Task.isCancelled, try store.read() == settings else { return raw }
            return result
        } catch {
            logger.notice("English dictation configuration unavailable; using raw transcript")
            return raw
        }
    }

    @concurrent
    static func process(
        _ raw: String, language: String?, settings: DictationCleanupSettings, key: String,
        client: any DictationCleanupClient, timeout: Duration = .seconds(4)
    ) async -> String {
        var enabled = settings
        enabled.isEnabled = true
        return await DictationCleanup.process(
            raw, language: language, settings: enabled, key: key, client: client, timeout: timeout,
            systemPrompt: DictationEnglishPrompt.system(settings: settings, language: language))
    }
}
