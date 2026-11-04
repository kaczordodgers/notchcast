import Foundation

extension DictationModelStore {
    func distillTranscriber(model: DictationModel) -> DistillTranscriber {
        DistillTranscriber { samples in
            try await self.transcribe(samples, model: model, language: nil)
        }
    }
}
