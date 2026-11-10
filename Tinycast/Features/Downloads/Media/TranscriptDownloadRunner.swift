import Foundation

struct TranscriptDownloadRunner: DownloadRunner {
    struct Options: Codable, Sendable {
        var language: String?
        var cookiesFromBrowser: String?
    }

    static let kind = "transcript"
    var kind: String { Self.kind }
    var tools: [DownloadTool] { [.ytDlp] }
    /// Produces the transcript when the link has no captions.
    let transcribe: @Sendable (DownloadJob, DownloadRunContext) async throws -> URL?

    @concurrent
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        guard let executable = context.tools.find(.ytDlp) else {
            throw MediaFailure(detail: DownloadTool.ytDlp.missingDetail)
        }
        let options = try job.options(Options.self)
        let staging = FileManager.default.temporaryDirectory.appending(path: ".captions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        let metadata = try await context.spawn(executable: executable, arguments: MediaArguments.originalLanguage(
            source: job.source, cookies: options.cookiesFromBrowser))
        let original = metadata.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = options.language ?? (original.isEmpty || original == "NA" ? nil : original)
        for automatic in [false, true] {
            // Each pass gets its own folder, so a track the other pass wrote never counts as this one's.
            let folder = staging.appending(path: automatic ? "automatic" : "manual")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let arguments = MediaArguments.captions(source: job.source, destination: folder, automatic: automatic,
                                                    language: language, cookies: options.cookiesFromBrowser)
            let result = try await fetch(arguments, executable, context, folder)
            if MediaArguments.retryCaptions(stderr: result.errors, wroteCaptions: try !captions(in: folder).isEmpty) {
                try await Task.sleep(for: MediaArguments.rateLimitPause)
                _ = try await fetch(arguments, executable, context, folder)
            }
            try Task.checkCancellation()
            for file in try captions(in: folder) {
                let text = CaptionText.plainText(try String(contentsOf: file, encoding: .utf8), automatic: automatic)
                guard !text.isEmpty else { continue }
                let name = file.deletingPathExtension().deletingPathExtension().lastPathComponent
                try Task.checkCancellation()
                return try JobOutput.publish(Data(text.utf8), in: context.destination, stem: name, suffix: ".txt")
            }
        }
        return try await transcribe(job, context)
    }

    // yt-dlp exits 1 when one track fails, even after it wrote another; that run still counts.
    private func fetch(_ arguments: [String], _ executable: URL, _ context: DownloadRunContext,
                       _ folder: URL) async throws -> ChildProcess.Result {
        do {
            return try await context.spawn(executable: executable, arguments: arguments)
        } catch let failure as ChildProcess.Failure
                    where MediaArguments.isRateLimited(failure.result.errors) || (try? captions(in: folder).isEmpty) == false {
            return failure.result
        }
    }

    private func captions(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ["vtt", "srt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
