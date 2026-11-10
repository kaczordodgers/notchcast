import Foundation

@MainActor
final class DictationFamily {
    typealias Process = @Sendable (
        _ raw: String, _ language: String?, _ english: Bool, _ onFallback: @Sendable () async -> Void
    ) async -> String

    private let process: Process
    private weak var coordinator: DictationCoordinator?
    private var cleanupEnabled = false
    private var historyEnabled = false
    var historySink: (@MainActor (String, String) -> Void)?

    init(process: @escaping Process) {
        self.process = process
    }

    func bind(_ coordinator: DictationCoordinator) {
        self.coordinator = coordinator
    }

    var isAvailable: Bool { coordinator?.isEnabled == true }
    var isRecording: Bool { coordinator?.triggerIsRecording == true }

    func start(inEnglish: Bool) { coordinator?.triggerStarted(inEnglish: inEnglish) }
    func finish() { coordinator?.triggerFinished() }
    func cancel() { coordinator?.cancel() }
    func cancelEnglish() { coordinator?.cancelEnglish() }

    func toggleEnglish() {
        if isRecording { finish() } else { start(inEnglish: true) }
    }

    func setCleanup(_ enabled: Bool) {
        cleanupEnabled = enabled
        installStages()
    }

    func setHistory(_ enabled: Bool) {
        historyEnabled = enabled
        installStages()
    }

    func installEnglish(onFailure: @escaping @MainActor () -> Void) {
        let process = process
        DictationCoordinator.englishTranscriptStage = { @MainActor [self] raw, language in
            let translated = await process(raw, language, true) { await onFailure() }
            observeTranscript(raw: raw, cleaned: translated)
            return translated
        }
    }

    func observeTranscript(raw: String, cleaned: String) {
        guard !Task.isCancelled, historyEnabled,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        historySink?(raw, cleaned)
    }

    private func installStages() {
        DictationCoordinator.transcriptObserver = historyEnabled ? { [self] raw, cleaned in
            observeTranscript(raw: raw, cleaned: cleaned)
        } : nil
        guard cleanupEnabled || historyEnabled else {
            DictationCoordinator.transcriptStage = nil
            return
        }
        let process = process
        DictationCoordinator.transcriptStage = { @MainActor [self] raw, language in
            cleanupEnabled ? await process(raw, language, false, {}) : raw
        }
    }
}
