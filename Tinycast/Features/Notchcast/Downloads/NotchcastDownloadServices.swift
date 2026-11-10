import Foundation

struct NotchcastDownloadServices: Sendable {
    let transcriber: DistillTranscriber
    let workDirectory: URL
    var releaseSpeech: @MainActor @Sendable () async -> Void = {}
    var tools = DownloadToolLookup()
    var saveWebpage: DistillRunner.SaveWebpage = { source, destination in
        try await WebpageSaver(destination: destination).save(source)
    }
    var trash: DistillConverter.Trash = { source in
        try FileManager.default.trashItem(at: source, resultingItemURL: nil)
    }

    func distillRunner(timestamps: @escaping @MainActor @Sendable () -> Bool) -> DistillRunner {
        DistillRunner(transcriber: transcriber, workDirectory: workDirectory, timestamps: timestamps,
                      saveWebpage: saveWebpage)
    }

    var transcriptRunner: TranscriptDownloadRunner {
        return TranscriptDownloadRunner(transcribe: { job, context in
            try await transcribeVideo(job, context: context)
        })
    }

    @concurrent
    private func transcribeVideo(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL {
        guard let cleaned = LinkCleaner.clean(job.source), let url = URL(string: cleaned), YtDlpAudio.isMedia(url) else {
            throw MediaFailure(detail: String(localized: "Transcript fallback requires a supported media link.", table: "Notchcast"))
        }
        return try await context.withDistillAudio(link: cleaned, workDirectory: workDirectory) { media, audio, work in
            let text = try await transcriber.text(file: audio, workDirectory: work, context: context)
            let title = media.id.map { "\(media.title) [\($0)]" } ?? media.title
            return try DistillRunner.save(text, name: DistillTranscript.fileName(channel: nil, title: title),
                                          in: context.destination)
        }
    }

    var convertRunner: DistillConvertRunner {
        DistillConvertRunner(html: Self.convertHTML, media: { source, context in
            let text = try await transcriber.text(file: source, workDirectory: workDirectory, context: context)
            return DistillConversion.literal(text, source: source, retainSource: true)
        }, trash: trash)
    }

    @concurrent
    private static func convertHTML(_ html: String, base: URL?, context: DownloadRunContext) async throws -> DistillConversion {
        try Task.checkCancellation()
        return DistillConversion(markdown: HTMLMarkdown.convert(html, baseURL: base ?? context.destination), retainSource: false)
    }
}
