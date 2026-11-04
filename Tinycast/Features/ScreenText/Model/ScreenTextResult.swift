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
            if paragraph.hasSuffix("-"), paragraph.dropLast().last?.isLetter == true,
                line.first?.isLowercase == true {
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
