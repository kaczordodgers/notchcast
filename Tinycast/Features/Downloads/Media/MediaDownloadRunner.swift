import Foundation

struct MediaDownloadRunner: DownloadRunner {
    let format: MediaArguments.Format
    var kind: String { format == .video ? "video" : "audio" }
    var tools: [DownloadTool] { [.ytDlp, .ffmpeg] }

    @concurrent
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        guard let executable = context.tools.find(.ytDlp) else {
            throw MediaFailure(detail: DownloadTool.ytDlp.missingDetail)
        }
        guard context.tools.find(.ffmpeg) != nil else {
            throw MediaFailure(detail: DownloadTool.ffmpeg.missingDetail)
        }
        try FileManager.default.createDirectory(at: context.destination, withIntermediateDirectories: true)
        let aria2 = job.options["aria2Enabled"] != "false" ? context.tools.find(.aria2c)?.path : nil
        func attempt(aria2Path: String?, restart: Bool = false) async throws -> ChildProcess.Result {
            let (stream, continuation) = AsyncStream<MediaOutput.Progress>.makeStream()
            async let reporting: Void = Self.report(stream, context: context)
            defer { continuation.finish() }
            let result = try await context.spawn(executable: executable, arguments: MediaArguments.download(
                source: job.source, destination: context.destination, format: format,
                aria2Path: aria2Path, cookies: job.options["cookiesFromBrowser"], restart: restart), onLine: { line in
                    guard let value = MediaOutput.progress(line) else { return }
                    continuation.yield(value)
                })
            continuation.finish()
            await reporting
            return result
        }
        let result: ChildProcess.Result
        do {
            result = try await attempt(aria2Path: aria2)
        } catch let failure as ChildProcess.Failure {
            try Task.checkCancellation()
            guard MediaArguments.retryNatively(stderr: failure.result.errors,
                                               source: job.source, usedAria2: aria2 != nil) else { throw failure }
            result = try await attempt(aria2Path: nil, restart: true)
        }
        try Task.checkCancellation()
        guard let output = result.output.split(whereSeparator: \.isNewline).reversed()
            .compactMap({ MediaOutput.outputPath(String($0), destination: context.destination) }).first,
            FileManager.default.fileExists(atPath: output.path) else {
            throw MediaFailure(detail: String(localized: "The downloader did not return an output file."))
        }
        return output
    }

    private static func report(_ stream: AsyncStream<MediaOutput.Progress>, context: DownloadRunContext) async {
        for await value in stream {
            guard !Task.isCancelled else { return }
            await context.report(DownloadProgress(
                fraction: value.fraction, received: value.received, total: value.total,
                bytesPerSecond: value.bytesPerSecond, eta: value.eta))
        }
    }
}
