import Foundation
import os

enum DictationCleanup {
    private static let logger = Logger(subsystem: "app.notchcast", category: "DictationCleanup")

    @concurrent
    static func process(_ raw: String, language: String?) async -> String {
        guard !Task.isCancelled, let identifier = Bundle.main.bundleIdentifier,
              let store = DictationCleanupSettingsStore.live(bundleIdentifier: identifier)
        else { return raw }
        do {
            let settings = try store.read()
            guard settings.isEnabled else { return raw }
            let key = try store.apiKey() ?? ""
            let result = await process(raw, language: language, settings: settings, key: key,
                                       client: DictationCleanupHTTPClient())
            guard !Task.isCancelled, try store.read() == settings else { return raw }
            return result
        } catch {
            logger.notice("Cleanup configuration unavailable; using raw transcript")
            return raw
        }
    }

    @concurrent
    static func process(
        _ raw: String, language: String?, settings: DictationCleanupSettings, key: String,
        client: any DictationCleanupClient, timeout: Duration = .seconds(4)
    ) async -> String {
        guard settings.isEnabled, !Task.isCancelled, !key.isEmpty,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              raw.count <= 32_768, timeout > .zero
        else { return raw }
        do {
            let request = try DictationCleanupHTTPClient.request(
                raw: raw, language: language, settings: settings, key: key)
            let deadline = ContinuousClock.now.advanced(by: timeout)
            let cleaned = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask { try await client.clean(request) }
                group.addTask {
                    try await Task.sleep(until: deadline, clock: .continuous)
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next().flatMap { $0 }
            }
            guard !Task.isCancelled, ContinuousClock.now < deadline, let cleaned,
                  DictationCleanupGuard.accepts(cleaned, raw: raw, vocabulary: settings.vocabulary)
            else { return raw }
            return cleaned
        } catch is CancellationError {
            return raw
        } catch {
            logger.notice("Cleanup request failed; using raw transcript")
            return raw
        }
    }
}
