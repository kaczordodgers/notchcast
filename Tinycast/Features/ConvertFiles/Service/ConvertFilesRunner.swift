import Foundation

nonisolated struct ConvertFilesRunner: DownloadRunner {
    typealias ProcessRunner = @Sendable (URL, [String], DownloadRunContext) async throws -> Void

    struct Options: Codable, Sendable {
        var sources: [String]
        var target: String
        var pages = ""
    }

    static let kind = "convert-files"
    var kind: String { Self.kind }
    let tools: [DownloadTool] = []
    var process: ProcessRunner = { executable, arguments, context in
        _ = try await context.spawn(executable: executable, arguments: arguments)
    }
    var post: @MainActor @Sendable (String) -> Void = { _ in }

    @concurrent
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        guard let options = try job.options(Options.self) else {
            throw ConvertFilesPlan.Failure(message: String(
                localized: "This conversion was queued by an older version. Add the files again.", table: "Notchcast"))
        }
        let sources = options.sources.map { URL(fileURLWithPath: $0) }
        let plan = try ConvertFilesPlan.make(sources: sources, target: options.target, pages: options.pages)
        var outputs: [URL] = []
        var failures: [String] = []
        for item in plan.items {
            try Task.checkCancellation()
            do {
                let published = try await execute(item, context: context)
                outputs.append(published)
                await post(published.lastPathComponent)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let detail = item.sources[0].lastPathComponent + ": " + error.localizedDescription
                failures.append(detail)
                await post(detail)
            }
        }
        try Task.checkCancellation()
        if !failures.isEmpty { throw ConvertFilesPlan.Failure(message: failures.joined(separator: "\n")) }
        return outputs.first
    }

    private func execute(_ item: ConvertFilesPlan.Item, context: DownloadRunContext) async throws -> URL {
        let manager = FileManager.default
        let folder = item.sources[0].deletingLastPathComponent()
        let scratch = folder.appending(path: ".convert-" + UUID().uuidString)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: scratch) }
        let staged = scratch.appending(path: item.stem + item.suffix)
        let arguments = item.arguments.map { $0 == ConvertFilesPlan.outputPlaceholder ? staged.path : $0 }
        if item.tool == "tar", arguments.first == "-x" {
            try manager.createDirectory(at: staged, withIntermediateDirectories: false)
        }
        if item.tool == "ffmpeg", !["srt", "ass", "ssa", "vtt"].contains(item.sources[0].pathExtension.lowercased()) {
            let probe = DownloadTool(name: "ffprobe", installCommand: "brew install ffmpeg")
            guard let path = context.tools.find(probe) else {
                throw ConvertFilesPlan.Failure(message: probe.missingDetail)
            }
            try await process(path, ["-v", "error", "-protocol_whitelist", "file,pipe,crypto,data",
                                     "-show_streams", "-show_format", "-of", "json", item.sources[0].path], context)
        }
        if item.tool == "native" {
            try await ConvertFilesNative.run(operation: arguments[0], format: arguments[1],
                                             inputs: item.sources, output: staged)
        } else {
            let tool = DownloadTool(name: item.tool, installCommand: "Install \(item.tool)")
            guard let executable = context.tools.find(tool) else {
                throw ConvertFilesPlan.Failure(message: tool.missingDetail)
            }
            try await process(executable, arguments, context)
        }
        try Task.checkCancellation()
        guard manager.fileExists(atPath: staged.path) else {
            throw ConvertFilesPlan.Failure(message: String(localized: "The conversion produced no output.", table: "Notchcast"))
        }
        return try JobOutput.publish(staged, in: folder, stem: item.stem, suffix: item.suffix)
    }
}
