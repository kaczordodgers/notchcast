import Foundation

nonisolated enum DistillAudioChunks {
    static let sampleRate = 16_000
    static let maximumSamples = sampleRate * 240
    static let overlapSamples = sampleRate * 2

    struct Chunk: Equatable, Sendable {
        let offset: Int64
        let count: Int
        var start: TimeInterval { Double(offset) / Double(sampleRate) }
    }

    static func plan(sampleCount: Int64) -> [Chunk] {
        guard sampleCount > 0 else { return [] }
        var chunks = [Chunk]()
        var offset: Int64 = 0
        while offset < sampleCount {
            let count = Int(min(Int64(maximumSamples), sampleCount - offset))
            chunks.append(Chunk(offset: offset, count: count))
            guard offset + Int64(count) < sampleCount else { break }
            offset += Int64(count - overlapSamples)
        }
        return chunks
    }

    static func removingOverlap(previous: String, next: String) -> String {
        let before = previous.split(whereSeparator: \.isWhitespace)
        let after = next.split(whereSeparator: \.isWhitespace)
        let limit = min(32, before.count, after.count)
        guard limit >= 2 else { return next.trimmingCharacters(in: .whitespacesAndNewlines) }
        for count in stride(from: limit, through: 2, by: -1) {
            let suffix = before.suffix(count).map(normalized)
            let prefix = after.prefix(count).map(normalized)
            if suffix == prefix, prefix.allSatisfy({ !$0.isEmpty }) {
                return after.dropFirst(count).joined(separator: " ")
            }
        }
        return next.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ word: Substring) -> String {
        String(word).lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}
