import Foundation

nonisolated struct DistillTranscriber: Sendable {
    typealias Recognize = @MainActor @Sendable ([Float]) async throws -> String
    typealias Progress = @Sendable (_ completed: Int, _ total: Int) async -> Void

    let recognize: Recognize

    func text(file: URL, workDirectory: URL, context: DownloadRunContext) async throws -> String {
        let segments = try await transcribe(file: file, workDirectory: workDirectory, context: context)
        let text = DistillTranscript.text(segments, times: false)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationWire.Failure.unavailable
        }
        return text
    }

    @concurrent
    func transcribe(
        file: URL, workDirectory: URL, context: DownloadRunContext,
        progress: @escaping Progress = { _, _ in }
    ) async throws -> [DistillTranscript.Segment] {
        try Task.checkCancellation()
        guard file.isFileURL, workDirectory.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let work = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let pcm = work.appending(path: "audio.f32")
        _ = try await context.distillSpawn(.ffmpeg, arguments: Self.arguments(input: file, output: pcm))
        return try await transcribePCM(file: pcm) { completed, total in
            await context.report(DownloadProgress(
                fraction: Double(completed) / Double(total),
                stage: String(localized: "Transcribing \(completed) of \(total)")))
            await progress(completed, total)
        }
    }

    @concurrent
    func transcribePCM(file: URL, progress: @escaping Progress = { _, _ in }) async throws -> [DistillTranscript.Segment] {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let bytes = try handle.seekToEnd()
        guard bytes > 0, bytes.isMultiple(of: 4), bytes / 4 <= UInt64(Int64.max) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let chunks = DistillAudioChunks.plan(sampleCount: Int64(bytes / 4))
        var segments = [DistillTranscript.Segment]()
        var previous = ""
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(chunk.offset) * 4)
            let data = try DictationWire.readExactly(chunk.count * 4, from: handle)
            let samples = data.withUnsafeBytes { bytes in
                (0..<chunk.count).map {
                    Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
                }
            }
            guard samples.allSatisfy(\.isFinite) else { throw CocoaError(.fileReadCorruptFile) }
            let recognized = try await recognize(samples)
            try Task.checkCancellation()
            let text = index == 0 ? recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                : DistillAudioChunks.removingOverlap(previous: previous, next: recognized)
            if !text.isEmpty { segments.append(.init(start: chunk.start, text: text)) }
            previous = recognized
            await progress(index + 1, chunks.count)
        }
        return segments
    }

    static func arguments(input: URL, output: URL) -> [String] {
        ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", input.path, "-map", "0:a:0", "-vn",
         "-ac", "1", "-ar", "16000", "-c:a", "pcm_f32le", "-f", "f32le", "-n", output.path]
    }
}
