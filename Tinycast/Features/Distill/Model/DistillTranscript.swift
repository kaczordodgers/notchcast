import Foundation

nonisolated enum DistillTranscript {
    struct Segment: Equatable, Sendable {
        let start: TimeInterval
        let text: String
    }

    static func text(_ segments: [Segment], times: Bool) -> String {
        let lines = segments.compactMap { segment -> String? in
            let words = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return nil }
            return times ? "\(clock(segment.start)) \(words)" : words
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, min(seconds, Double(Int32.max)))) : 0
        return String(format: "[%02d:%02d:%02d]", whole / 3600, whole / 60 % 60, whole % 60)
    }

    static func fileName(channel: String?, title: String) -> String {
        let parts = [channel, title].compactMap { $0.map(clean) }.filter { !$0.isEmpty }
        return (parts.isEmpty ? "Untitled" : parts.joined(separator: " - ")) + ".txt"
    }

    private static func clean(_ text: String) -> String {
        let replaced = String(text.replacingOccurrences(of: ": ", with: " - ").unicodeScalars.map { scalar -> Character in
            "/:\\<>\"|?*".unicodeScalars.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
                ? "-" : Character(scalar)
        })
        let spaced = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var result = ""
        for character in spaced {
            guard result.utf8.count + String(character).utf8.count <= 100 else { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}
