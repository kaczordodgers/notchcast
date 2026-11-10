import Foundation

nonisolated struct DistillRunner: DownloadRunner {
    typealias SaveWebpage = @Sendable (_ source: URL, _ destination: URL) async throws -> URL

    static let kind = "distill"
    let transcriber: DistillTranscriber
    let workDirectory: URL
    let saveWebpage: SaveWebpage
    /// Read when a job begins, so one that waited in the queue follows the switch as it is then.
    var timestamps: @MainActor @Sendable () -> Bool = { false }
    var kind: String { Self.kind }
    let tools: [DownloadTool] = [.ytDlp, .ffmpeg]

    init(transcriber: DistillTranscriber, workDirectory: URL, saveWebpage: @escaping SaveWebpage) {
        self.transcriber = transcriber
        self.workDirectory = workDirectory
        self.saveWebpage = saveWebpage
    }

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        try await run(source: job.source, destination: context.destination, times: timestamps(), context: context)
    }

    @concurrent
    func run(
        source: String, destination: URL, times: Bool = false, context: DownloadRunContext,
        progress: @escaping DistillTranscriber.Progress = { _, _ in }
    ) async throws -> URL {
        try Task.checkCancellation()
        guard let cleaned = LinkCleaner.clean(source), let url = URL(string: cleaned) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard YtDlpAudio.isMedia(url) else { return try await saveWebpage(url, destination) }
        return try await context.withDistillAudio(link: cleaned, workDirectory: workDirectory) { media, audio, work in
            let segments = try await transcriber.transcribe(
                file: audio, workDirectory: work, context: context, progress: progress)
            let text = DistillTranscript.text(segments, times: times)
            try Task.checkCancellation()
            return try Self.save(text, name: DistillTranscript.fileName(channel: media.channel, title: media.title), in: destination)
        }
    }

    static func save(_ text: String, name: String, in folder: URL) throws -> URL {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationWire.Failure.unavailable
        }
        guard name == URL(filePath: name).lastPathComponent, name.hasSuffix(".txt") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return try JobOutput.publish(Data(text.utf8), in: folder, stem: String(name.dropLast(4)), suffix: ".txt")
    }
}
