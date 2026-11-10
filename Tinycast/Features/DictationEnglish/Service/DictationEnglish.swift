import Foundation

enum DictationEnglish {
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
