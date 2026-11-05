import Foundation

nonisolated struct DistillRunner: DownloadRunner {
    typealias SaveWebpage = @Sendable (_ source: URL, _ destination: URL) async throws -> URL

    let transcriber: DistillTranscriber
    let workDirectory: URL
    let saveWebpage: SaveWebpage
    let kind = "distill"
    let tools: [DownloadTool] = [.ytDlp, .ffmpeg]

    init(transcriber: DistillTranscriber, workDirectory: URL,
         saveWebpage: @escaping SaveWebpage = { _, _ in
             throw NSError(domain: "Distill", code: 2, userInfo: [
                 NSLocalizedDescriptionKey: String(localized: "Webpage saving is not connected to Distill yet.", table: "Notchcast")
             ])
         }) {
        self.transcriber = transcriber
        self.workDirectory = workDirectory
        self.saveWebpage = saveWebpage
    }

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        try await run(source: job.source, destination: context.destination,
                      times: job.options["timestamps"] == "true", context: context)
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
        let work = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let metadata = try await context.distillSpawn(.ytDlp, arguments: YtDlpAudio.metadataArguments(link: cleaned))
        let media = try JSONDecoder().decode(YtDlpAudio.Media.self, from: Data(metadata.utf8))
        _ = try await context.distillSpawn(.ytDlp, arguments: YtDlpAudio.audioArguments(link: cleaned, folder: work))
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: [.isRegularFileKey])
        let audioFiles = try files.filter {
            guard $0.lastPathComponent.hasPrefix("audio."), !["part", "ytdl", "json"].contains($0.pathExtension) else {
                return false
            }
            return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
        guard audioFiles.count == 1, let audio = audioFiles.first else { throw CocoaError(.fileReadCorruptFile) }
        let segments = try await transcriber.transcribe(
            file: audio, workDirectory: work, context: context, progress: progress)
        let text = DistillTranscript.text(segments, times: times)
        try Task.checkCancellation()
        return try Self.save(text, name: DistillTranscript.fileName(channel: media.channel, title: media.title), in: destination)
    }

    static func save(_ text: String, name: String, in folder: URL) throws -> URL {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationWire.Failure.unavailable
        }
        guard name == URL(filePath: name).lastPathComponent, name.hasSuffix(".txt") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appending(path: ".\(UUID().uuidString).partial")
        try Data(text.utf8).write(to: partial, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: partial) }
        let base = String(name.dropLast(4))
        var number = 1
        while true {
            try Task.checkCancellation()
            let target = folder.appending(path: number == 1 ? name : "\(base) (\(number)).txt")
            do {
                try FileManager.default.linkItem(at: partial, to: target)
                return target
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                number += 1
            }
        }
    }
}
