import Foundation

extension DictationCleanup {
    @MainActor
    static func install() {
        DictationCoordinator.transcriptStage = { raw, language in
            await process(raw, language: language)
        }
    }
}
