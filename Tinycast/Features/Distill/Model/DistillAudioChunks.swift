import Foundation

nonisolated enum DistillAudioChunks {
    static let sampleRate = 16_000
    static let maximumSamples = sampleRate * 240

    struct Chunk: Equatable, Sendable {
        let offset: Int64
        let count: Int
        var start: TimeInterval { Double(offset) / Double(sampleRate) }
    }

    static func cut(in samples: [Float], final: Bool) -> Int {
        final ? samples.count : DictationAudioChunks.liveCut(in: samples, from: 0, to: samples.count)
    }
}
