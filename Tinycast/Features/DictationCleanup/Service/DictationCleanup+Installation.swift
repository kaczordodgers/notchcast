import Foundation

extension DictationCleanup {
    @MainActor static var transcriptObserver: (@MainActor (String, String) -> Void)?
    @MainActor private static var cleanupEnabled = false
    @MainActor private static var historyEnabled = false

    @MainActor
    static func setHistoryEnabled(_ enabled: Bool) {
        historyEnabled = enabled
        updateStage()
    }

    @MainActor
    static func uninstall() {
        cleanupEnabled = false
        updateStage()
    }

    @MainActor
    static func install() {
        cleanupEnabled = true
        updateStage()
    }

    @MainActor
    static func observeTranscript(raw: String, cleaned: String) {
        if !Task.isCancelled, historyEnabled,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transcriptObserver?(raw, cleaned)
        }
    }

    @MainActor
    private static func updateStage() {
        guard cleanupEnabled || historyEnabled else {
            DictationCoordinator.transcriptStage = nil
            return
        }
        DictationCoordinator.transcriptStage = { @MainActor raw, language in
            let cleaned = cleanupEnabled ? await process(raw, language: language) : raw
            observeTranscript(raw: raw, cleaned: cleaned)
            return cleaned
        }
    }
}
