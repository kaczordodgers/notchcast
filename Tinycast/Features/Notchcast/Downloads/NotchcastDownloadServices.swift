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

    var distillRunner: DistillRunner {
        DistillRunner(transcriber: transcriber, workDirectory: workDirectory, saveWebpage: saveWebpage)
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
        let work = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let metadata = try await context.distillSpawn(.ytDlp, arguments: YtDlpAudio.metadataArguments(link: cleaned))
        struct Metadata: Decodable { let title: String; let id: String }
        let first = metadata.split(whereSeparator: \.isNewline).first ?? ""
        let media = try JSONDecoder().decode(Metadata.self, from: Data(first.utf8))
        _ = try await context.distillSpawn(.ytDlp, arguments: YtDlpAudio.audioArguments(link: cleaned, folder: work))
        let files = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: [.isRegularFileKey])
        let audio = try files.filter {
            guard $0.lastPathComponent.hasPrefix("audio."),
                  !["part", "ytdl", "json"].contains($0.pathExtension) else { return false }
            return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
        guard audio.count == 1 else { throw CocoaError(.fileReadCorruptFile) }
        let text = try await transcriber.text(file: audio[0], workDirectory: work, context: context)
        return try DistillRunner.save(text,
            name: DistillTranscript.fileName(channel: nil, title: "\(media.title) [\(media.id)]"), in: context.destination)
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
