import Foundation

nonisolated enum CaptionText {
    static func plainText(_ source: String, automatic: Bool) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let cue = block.components(separatedBy: "\n")
            guard let timing = cue.firstIndex(where: { $0.contains(" --> ") }) else { continue }
            let next = cue.dropFirst(timing + 1).map(clean).filter { !$0.isEmpty }
            // Rolling cues repeat earlier lines; a manual cue repeated whole was said twice.
            var overlap = min(lines.count, automatic ? next.count : max(next.count - 1, 0))
            while overlap > 0, Array(lines.suffix(overlap)) != Array(next.prefix(overlap)) { overlap -= 1 }
            lines.append(contentsOf: next.dropFirst(overlap))
        }
        return lines.joined(separator: " ")
    }

    private static func clean(_ line: String) -> String {
        HTMLDocument.decode(line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
