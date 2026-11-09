import Foundation

nonisolated enum CaptionText {
    static func plainText(_ source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let cue = block.components(separatedBy: "\n")
            guard let timing = cue.firstIndex(where: { $0.contains(" --> ") }) else { continue }
            let next = cue.dropFirst(timing + 1).map(clean).filter { !$0.isEmpty }
            // Rolling captions repeat the previous cue's last lines before adding new ones.
            var overlap = min(lines.count, next.count)
            while overlap > 0, Array(lines.suffix(overlap)) != Array(next.prefix(overlap)) { overlap -= 1 }
            lines.append(contentsOf: next.dropFirst(overlap))
        }
        return lines.joined(separator: " ")
    }

    private static func clean(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
