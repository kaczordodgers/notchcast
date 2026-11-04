import Foundation

@MainActor
final class VoiceAskRecording {
    private let capture = DictationCapture()
    private let core: AppCore
    private var cleanup: Task<Void, Never>?
    private var starting: Task<Void, Error>?

    init(core: AppCore) { self.core = core }

    func begin() async throws {
        await cleanup?.value
        try Task.checkCancellation()
        let task = Task { [capture, core] in
            try Task.checkCancellation()
            try await capture.start(microphoneID: core.settings.dictationMicrophone)
            try Task.checkCancellation()
        }
        starting = task
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func finish() async throws -> String {
        let samples = await capture.stop()
        try Task.checkCancellation()
        return try await core.dictationModels.transcribe(
            samples, model: core.settings.dictationModel, language: core.settings.dictationLanguage)
    }

    func cancel() {
        let previous = cleanup
        let starting = starting
        starting?.cancel()
        cleanup = Task { [capture] in
            await previous?.value
            _ = await starting?.result
            _ = await capture.stop()
        }
    }
}
