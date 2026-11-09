import Observation

@MainActor @Observable final class DictationCoordinator {
    static var transcriptStage: (@Sendable (String, String?) async -> String)?
    static var transcriptObserver: ((String, String) -> Void)?
    static var englishTranscriptStage: (@Sendable (String, String?) async -> String)?
    var isEnabled = true
    var triggerIsRecording = false
    var starts = 0
    var finishes = 0
    var cancels = 0
    var englishCancels = 0
    func triggerStarted(inEnglish: Bool) { precondition(inEnglish); starts += 1; triggerIsRecording = true }
    func triggerFinished() { finishes += 1; triggerIsRecording = false }
    func cancel() { cancels += 1 }
    func cancelEnglish() { englishCancels += 1; triggerIsRecording = false }
}

extension DictationFamily {
    static let shared = DictationFamily(process: { raw, _, english, onFallback in
        if english { await onFallback() }
        return raw
    })
}
