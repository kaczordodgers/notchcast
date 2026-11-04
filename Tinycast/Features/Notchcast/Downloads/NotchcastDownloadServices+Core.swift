import Foundation

extension NotchcastDownloadServices {
    @MainActor
    init(core: AppCore) {
        let models = DictationModelStore(idleRelease: .never)
        self.init(transcriber: DistillTranscriber { [weak core] samples in
            guard let core else { throw CancellationError() }
            guard !core.dictationModels.transcribing, !models.transcribing else {
                throw DictationWire.Failure.busy
            }
            models.refreshInstalledModels()
            return try await models.transcribe(samples, model: core.settings.dictationModel, language: nil)
        }, workDirectory: AppPaths.caches().appending(path: "Notchcast/Transcription"),
                  releaseSpeech: { await models.release() })
    }
}
