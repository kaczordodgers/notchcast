import Foundation

extension DownloadRunContext {
    func distillSpawn(_ tool: DownloadTool, arguments: [String]) async throws -> String {
        guard let executable = tools.find(tool) else { throw DownloadToolMissing(tool: tool) }
        return try await spawn(executable: executable, arguments: arguments).output
    }

    /// Fetches a media link's audio into a scratch folder that is removed when `body` returns.
    func withDistillAudio<Output>(
        link: String, workDirectory: URL,
        _ body: (_ media: YtDlpAudio.Media, _ audio: URL, _ work: URL) async throws -> Output
    ) async throws -> Output {
        let work = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let metadata = try await distillSpawn(.ytDlp, arguments: YtDlpAudio.metadataArguments(link: link))
        // A playlist link prints one JSON line per entry; the first is the linked media.
        let first = metadata.split(whereSeparator: \.isNewline).first ?? ""
        let media = try JSONDecoder().decode(YtDlpAudio.Media.self, from: Data(first.utf8))
        _ = try await distillSpawn(.ytDlp, arguments: YtDlpAudio.audioArguments(link: link, folder: work))
        try Task.checkCancellation()
        let audio = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: [.isRegularFileKey])
            .filter {
                guard $0.lastPathComponent.hasPrefix("audio."), !["part", "ytdl", "json"].contains($0.pathExtension) else {
                    return false
                }
                return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
        guard audio.count == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return try await body(media, audio[0], work)
    }
}
