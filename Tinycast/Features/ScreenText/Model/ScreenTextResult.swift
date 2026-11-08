import Foundation

struct ScreenTextResult: Sendable, Equatable {
    enum Kind: Sendable { case text, qrCode, barcode }
    let content: String
    let kind: Kind

    static func removingLineBreaks(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var paragraphs: [String] = []
        var paragraph = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                if !paragraph.isEmpty { paragraphs.append(paragraph); paragraph = "" }
                continue
            }
            let previousWord = paragraph.split(whereSeparator: { $0.isWhitespace }).last ?? ""
            var nextWord = line.split(whereSeparator: { $0.isWhitespace }).first ?? ""
            while let last = nextWord.last, ".,;:!?)]}\"'“”„’‘«»‹›…".contains(last) { nextWord.removeLast() }
            if paragraph.hasSuffix("-"), !previousWord.dropLast().isEmpty,
                previousWord.dropLast().allSatisfy({ $0.isLetter && $0.isLowercase }),
                !nextWord.isEmpty, nextWord.allSatisfy({ $0.isLetter && $0.isLowercase }) {
                paragraph.removeLast()
                paragraph += line
            } else {
                if !paragraph.isEmpty { paragraph += " " }
                paragraph += line
            }
        }
        if !paragraph.isEmpty { paragraphs.append(paragraph) }
        return paragraphs.joined(separator: "\n\n")
    }
}
