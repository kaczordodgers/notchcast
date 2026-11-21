import Foundation

extension IslandNotice {
    static let dictationID = "dictation"

    /// The live session's notice; nil while nothing is listening or the session is ending.
    init?(dictation session: DictationIslandSession, keysFocused: Bool = true) {
        switch session.phase {
        case .idle, .ending:
            return nil
        case .recording:
            let hint =
                session.copies
                ? String(localized: "Return to Copy · Esc to Cancel", table: "Notchcast")
                : String(localized: "Return to Paste · Esc to Cancel", table: "Notchcast")
            let recording = String(localized: "Recording dictation", table: "Notchcast")
            let spoken = String(localized: "Recording dictation, Return to finish, Escape to cancel", table: "Notchcast")
            let showsHint = keysFocused && session.holdsKeys
            self.init(
                id: Self.dictationID, symbol: "mic", text: showsHint ? hint : recording,
                progress: IslandProgress(fraction: nil, headline: true, readout: session.elapsed),
                spokenText: showsHint ? spoken : recording, meter: session.meter)
        case .transcribing:
            self.init(
                id: Self.dictationID, symbol: "waveform", text: String(localized: "Transcribing", table: "Notchcast"),
                progress: IslandProgress(fraction: nil, headline: false))
        case .cleaningUp:
            self.init(
                id: Self.dictationID, symbol: "sparkles", text: String(localized: "Cleaning Up", table: "Notchcast"),
                progress: IslandProgress(fraction: nil, headline: false))
        }
    }

    /// A session's result: a quiet check for text delivered, a red notice for anything lost.
    init(dictation outcome: DictationIslandSession.Outcome) {
        let failure = "exclamationmark.triangle"
        switch outcome {
        case .pasted:
            self.init(id: Self.dictationID, symbol: "checkmark",
                      text: String(localized: "Pasted", table: "Notchcast"), quiet: true)
        case .copied:
            self.init(id: Self.dictationID, symbol: "checkmark", text: String(localized: "Copied"), quiet: true)
        case .noSpeech:
            self.init(id: Self.dictationID, symbol: "mic.slash",
                      text: String(localized: "No Speech Detected", table: "Notchcast"))
        case .pastedRaw:
            self.init(id: Self.dictationID, symbol: failure,
                      text: String(localized: "Pasted Without Cleanup", table: "Notchcast"), isFailure: true)
        case .copiedRaw:
            self.init(id: Self.dictationID, symbol: failure,
                      text: String(localized: "Copied Without Cleanup", table: "Notchcast"), isFailure: true)
        case .noCleanupModel(let copies):
            let text = copies
                ? String(localized: "No Cleanup Model · Copied Raw", table: "Notchcast")
                : String(localized: "No Cleanup Model · Pasted Raw", table: "Notchcast")
            self.init(id: Self.dictationID, symbol: failure, text: text, isFailure: true,
                      spokenText: copies ? nil : DictationIslandSession.missingCleanupModel)
        case .pasteFailed:
            self.init(id: Self.dictationID, symbol: failure,
                      text: String(localized: "Couldn't Paste", table: "Notchcast"), isFailure: true)
        case .partLost:
            self.init(id: Self.dictationID, symbol: failure,
                      text: String(localized: "Some Text Wasn't Pasted", table: "Notchcast"), isFailure: true)
        case .failed:
            self.init(id: Self.dictationID, symbol: failure,
                      text: String(localized: "Dictation Failed", table: "Notchcast"), isFailure: true)
        }
    }
}
