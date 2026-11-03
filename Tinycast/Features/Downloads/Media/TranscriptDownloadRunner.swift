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
        let staging = FileManager.default.temporaryDirectory.appending(path: ".captions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let metadata = try await context.spawn(executable: executable, arguments: MediaArguments.originalLanguage(
            source: job.source, cookies: job.options["cookiesFromBrowser"]))
        let original = metadata.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = job.options["language"] ?? (original.isEmpty || original == "NA" ? nil : original)
        for automatic in [false, true] {
            _ = try await context.spawn(executable: executable, arguments: MediaArguments.captions(
                source: job.source, destination: staging, automatic: automatic,
                language: language, cookies: job.options["cookiesFromBrowser"]))
            try Task.checkCancellation()
            let files = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .filter { ["vtt", "srt"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                let text = CaptionText.plainText(try String(contentsOf: file, encoding: .utf8), automatic: automatic)
                guard !text.isEmpty else { continue }
                let name = file.deletingPathExtension().deletingPathExtension().lastPathComponent
                var output = context.destination.appending(path: name + ".txt")
                var suffix = 2
                while FileManager.default.fileExists(atPath: output.path) {
                    output = context.destination.appending(path: name + " (\(suffix)).txt")
                    suffix += 1
                }
                try FileManager.default.createDirectory(at: context.destination, withIntermediateDirectories: true)
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
