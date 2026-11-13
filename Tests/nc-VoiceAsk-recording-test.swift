// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskRecording.swift

import Foundation

@MainActor
final class DictationCapture {
    static var samples: [Float] = []
    func start(microphoneID: String) async throws {}
    func stop() async -> [Float] { Self.samples }
}

@MainActor
final class AppCore {
    struct Settings {
        let dictationMicrophone = "fixture"
        let dictationModel = "fixture"
        let dictationLanguage = "en"
    }

    @MainActor final class Models {
        var calls = 0
        func transcribe(_ samples: [Float], model: String, language: String) async throws -> String {
            calls += 1
            guard !samples.isEmpty else { throw CocoaError(.fileReadUnknown) }
            precondition(samples == [0.5] && model == "fixture" && language == "en")
            return "fixture speech"
        }
    }

    let settings = Settings()
    let dictationModels = Models()
}

@main
struct VoiceAskRecordingTest {
    @MainActor static func main() async throws {
        let core = AppCore()
        let recording = VoiceAskRecording(core: core)
        try await recording.begin()
        let empty = try await recording.finish()
        precondition(empty.isEmpty && core.dictationModels.calls == 0)
        DictationCapture.samples = [0.5]
        try await recording.begin()
        let speech = try await recording.finish()
        precondition(speech == "fixture speech" && core.dictationModels.calls == 1)
        print("PASS: empty recording skips transcription; recorded speech is transcribed")
    }
}
