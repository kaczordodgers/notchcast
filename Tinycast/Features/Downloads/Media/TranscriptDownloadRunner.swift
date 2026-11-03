import Foundation

struct TranscriptDownloadRunner: DownloadRunner {
    let kind = "transcript"
    var tools: [DownloadTool] { [.ytDlp] }
    var transcribe: (@Sendable (DownloadJob, DownloadRunContext) async throws -> URL?)?

    @concurrent
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        guard let executable = context.tools.find(.ytDlp) else {
            throw MediaFailure(detail: DownloadTool.ytDlp.missingDetail)
        }
        let staging = context.destination.appending(path: ".captions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for automatic in [false, true] {
            _ = try await context.spawn(executable: executable, arguments: MediaArguments.captions(
                source: job.source, destination: staging, automatic: automatic,
                language: job.options["language"] ?? "en", cookies: job.options["cookiesFromBrowser"]))
            try Task.checkCancellation()
            let files = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .filter { ["vtt", "srt"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                let text = CaptionText.plainText(try String(contentsOf: file, encoding: .utf8))
                guard !text.isEmpty else { continue }
                let name = file.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString + ".txt"
                let output = context.destination.appending(path: name)
                try Task.checkCancellation()
                try text.write(to: output, atomically: true, encoding: .utf8)
                return output
            }
        }
        if let transcribe { return try await transcribe(job, context) }
        throw MediaFailure(detail: String(localized:
            "No captions are available. The Distill transcriber fallback is not connected yet."))
    }
}
