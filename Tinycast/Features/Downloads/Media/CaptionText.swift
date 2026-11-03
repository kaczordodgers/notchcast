import Foundation

nonisolated enum CaptionText {
    static func plainText(_ source: String, automatic: Bool = false) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var words: [String] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            guard let timing = lines.firstIndex(where: { $0.contains(" --> ") }) else { continue }
            let text = lines.dropFirst(timing + 1).joined(separator: " ")
                .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
            let next = text.split(whereSeparator: \.isWhitespace).map(String.init)
            var overlap = automatic ? min(words.count, next.count) : 0
            while overlap > 0, Array(words.suffix(overlap)) != Array(next.prefix(overlap)) { overlap -= 1 }
            words.append(contentsOf: next.dropFirst(overlap))
        }
        return words.joined(separator: " ")
    }
}
