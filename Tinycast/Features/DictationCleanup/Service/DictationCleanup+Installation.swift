import Foundation

extension DictationCleanup {
    @MainActor static var transcriptObserver: (@MainActor (String, String) async -> Void)?
    @MainActor
    static func install() {
        DictationCoordinator.transcriptStage = { raw, language in
            let cleaned = await process(raw, language: language)
            if !Task.isCancelled { await transcriptObserver?(raw, cleaned) }
            return cleaned
        }
    }
}
