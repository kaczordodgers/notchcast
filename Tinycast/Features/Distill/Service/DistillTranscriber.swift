import Foundation

nonisolated struct DistillTranscriber: Sendable {
    typealias Recognize = @MainActor @Sendable ([Float]) async throws -> String
    typealias Progress = @Sendable (_ completed: Int, _ total: Int) async -> Void

    let recognize: Recognize

    @MainActor
    func recognizeWhenAvailable(_ samples: [Float]) async throws -> String {
        while true {
            try Task.checkCancellation()
            do {
                return try await recognize(samples)
            } catch DictationWire.Failure.busy {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

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
                stage: String(localized: "Transcribing \(completed) of \(total)", table: "Notchcast")))
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
        let sampleCount = Int64(bytes / 4)
        var segments = [DistillTranscript.Segment]()
        var offset: Int64 = 0
        var completed = 0
        while offset < sampleCount {
            try Task.checkCancellation()
            let chunk = DistillAudioChunks.Chunk(
                offset: offset, count: Int(min(Int64(DistillAudioChunks.maximumSamples), sampleCount - offset)))
            try handle.seek(toOffset: UInt64(chunk.offset) * 4)
            let data = try DictationWire.readExactly(chunk.count * 4, from: handle)
            let samples = data.withUnsafeBytes { bytes in
                (0..<chunk.count).map {
                    Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
                }
            }
            guard samples.allSatisfy(\.isFinite) else { throw CocoaError(.fileReadCorruptFile) }
            let cut = DistillAudioChunks.cut(in: samples, final: offset + Int64(chunk.count) == sampleCount)
            let recognized = try await recognizeWhenAvailable(Array(samples.prefix(cut)))
            try Task.checkCancellation()
            let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { segments.append(.init(start: chunk.start, text: text)) }
            offset += Int64(cut)
            completed += 1
            let remaining = sampleCount - offset
            let estimated = Int((remaining + Int64(DistillAudioChunks.maximumSamples) - 1)
                / Int64(DistillAudioChunks.maximumSamples))
            await progress(completed, completed + estimated)
        }
        return segments
    }

    static func arguments(input: URL, output: URL) -> [String] {
        ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", input.path, "-map", "0:a:0", "-vn",
         "-ac", "1", "-ar", "16000", "-c:a", "pcm_f32le", "-f", "f32le", "-n", output.path]
    }
}
