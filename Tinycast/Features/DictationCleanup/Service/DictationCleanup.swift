import Foundation
import os

enum DictationCleanup {
    private static let logger = Logger(subsystem: NotchcastIdentity.releaseBundleIdentifier, category: "DictationCleanup")

    @concurrent
    static func process(
        _ raw: String, language: String?, settings: DictationCleanupSettings, key: String,
        client: any DictationCleanupClient, timeout: Duration = .seconds(4), systemPrompt: String? = nil,
        onFallback: @Sendable () async -> Void = {}
    ) async -> String {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return raw }
        guard settings.isEnabled, !Task.isCancelled, !key.isEmpty,
              raw.count <= 32_768, timeout > .zero
        else {
            if !Task.isCancelled { await onFallback() }
            return raw
        }
        do {
            var request = try DictationCleanupHTTPClient.request(
                raw: raw, language: language, settings: settings, key: key, systemPrompt: systemPrompt)
            request.timeoutInterval = Double(timeout.components.seconds)
                + Double(timeout.components.attoseconds) / 1e18
            let deadline = ContinuousClock.now.advanced(by: timeout)
            let cleaned = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask { [request] in try await client.clean(request) }
                group.addTask {
                    try await Task.sleep(until: deadline, clock: .continuous)
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next().flatMap { $0 }
            }
            guard !Task.isCancelled, ContinuousClock.now < deadline, let cleaned,
                  systemPrompt == nil
                    ? DictationCleanupGuard.accepts(cleaned, raw: raw, vocabulary: settings.vocabulary)
                    : (!cleaned.isEmpty && cleaned.count <= raw.count * 4 + 128)
            else {
                if !Task.isCancelled { await onFallback() }
                return raw
            }
            return cleaned
        } catch is CancellationError {
            return raw
        } catch {
            logger.notice("Cleanup request failed; using raw transcript")
            if !Task.isCancelled { await onFallback() }
            return raw
        }
    }
}
