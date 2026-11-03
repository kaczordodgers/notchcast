import Foundation

enum HTMLMarkdown {
    static func convert(_ html: String, baseURL: URL) -> String {
        let document = HTMLDocument(html)
        let raw = render(document.root, baseURL: baseURL).trimmingCharacters(in: .whitespacesAndNewlines)
        var fence: String?
        var lines: [String] = []
        for rawLine in raw.components(separatedBy: "\n") {
            let line = fence == nil && rawLine.allSatisfy(\.isWhitespace) ? "" : rawLine
            if let current = fence {
                lines.append(line)
                if line == current { fence = nil }
            } else {
                if line.hasPrefix("```") { fence = String(line.prefix(while: { $0 == "`" })) }
                if !line.isEmpty || lines.last != "" { lines.append(line) }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func render(_ node: HTMLDocument.Node, baseURL: URL, depth: Int = 0) -> String {
        guard depth < 128, !HTMLDocument.dropped.contains(node.tag), node.attributes["hidden"] == nil,
              node.attributes["aria-hidden"] != "true" else { return "" }
        if node.tag == "#text" { return escape(collapsed(node.text)) }
        if node.tag == "pre" {
            let text = node.plainText.trimmingCharacters(in: .newlines)
            let fence = String(repeating: "`", count: max(3, longestBackticks(text) + 1))
            let language = node.children.first?.attributes["class"]?.split(separator: " ")
                .first(where: { $0.hasPrefix("language-") }).map { String($0.dropFirst(9)) } ?? ""
            return "\n\n\(fence)\(language)\n\(text)\n\(fence)\n\n"
        }
        if node.tag == "code" {
            let text = collapsed(node.plainText)
            let fence = String(repeating: "`", count: max(1, longestBackticks(text) + 1))
            let padding = text.contains("`") || text.hasPrefix(" ") || text.hasSuffix(" ") ? " " : ""
            return "\(fence)\(padding)\(text)\(padding)\(fence)"
        }
        if node.tag == "ul" || node.tag == "ol" { return list(node, baseURL: baseURL, depth: depth) }
        if node.tag == "table" { return table(node, baseURL: baseURL, depth: depth) }
        let content = node.children.map { render($0, baseURL: baseURL, depth: depth + 1) }.joined()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        switch node.tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            return "\n\n\(String(repeating: "#", count: Int(node.tag.suffix(1)) ?? 1)) \(trimmed)\n\n"
        case "p", "div", "section", "article", "main", "header", "figure", "figcaption", "dl", "dt", "dd":
            return trimmed.isEmpty ? "" : "\n\n\(trimmed)\n\n"
        case "br": return "  \n"
        case "hr": return "\n\n---\n\n"
        case "strong", "b": return trimmed.isEmpty ? "" : "**\(trimmed)**"
        case "em", "i": return trimmed.isEmpty ? "" : "*\(trimmed)*"
        case "del", "s": return trimmed.isEmpty ? "" : "~~\(trimmed)~~"
        case "blockquote":
            return "\n\n" + trimmed.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n") + "\n\n"
        case "a":
            guard !trimmed.isEmpty else { return "" }
            guard let url = absolute(node.attributes["href"], baseURL: baseURL, image: false) else { return content }
            return "[\(trimmed)](<\(url)>)"
        case "img":
            guard let url = absolute(imageSource(node), baseURL: baseURL, image: true) else { return "" }
            return "![\(escape(node.attributes["alt"] ?? ""))](<\(url)>)"
        default: return content
        }
    }

    private static func list(_ node: HTMLDocument.Node, baseURL: URL, depth: Int) -> String {
        var number = Int(node.attributes["start"] ?? "") ?? 1
        let items = node.children.filter { $0.tag == "li" }.map { item in
            let marker = node.tag == "ol" ? "\(number). " : "- "
            number += 1
            let text = item.children.map { render($0, baseURL: baseURL, depth: depth + 1) }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = text.components(separatedBy: "\n")
            return marker + lines.enumerated().map { index, line in
                index == 0 ? line : String(repeating: " ", count: marker.count) + line
            }.joined(separator: "\n")
        }
        return "\n\n" + items.joined(separator: "\n") + "\n\n"
    }

    private static func table(_ node: HTMLDocument.Node, baseURL: URL, depth: Int) -> String {
        let rows = node.descendants(tag: "tr").map { row in
            row.children.filter { $0.tag == "th" || $0.tag == "td" }.map { cell in
                render(cell, baseURL: baseURL, depth: depth + 1)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "\n", with: " ")
            }
        }.filter { !$0.isEmpty }
        guard let width = rows.map(\.count).max(), width > 0 else { return "" }
        let formatted = rows.map { row in "| " + (row + Array(repeating: "", count: width - row.count))
            .joined(separator: " | ") + " |" }
        let divider = "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"
        return "\n\n" + ([formatted[0], divider] + formatted.dropFirst()).joined(separator: "\n") + "\n\n"
    }

    private static func imageSource(_ node: HTMLDocument.Node) -> String? {
        let source = node.attributes["src"] ?? ""
        if !source.isEmpty, !source.hasPrefix("data:") { return source }
        return node.attributes["data-src"] ?? node.attributes["data-original"]
            ?? node.attributes["srcset"]?.split(separator: ",").first?.split(separator: " ").first.map(String.init)
    }

    private static func absolute(_ value: String?, baseURL: URL, image: Bool) -> String? {
        guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines),
                                      relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              (image ? ["http", "https"] : ["http", "https", "mailto", "tel"]).contains(scheme) else { return nil }
        return url.absoluteString.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
    }

    private static func collapsed(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func escape(_ text: String) -> String {
        text.reduce(into: "") { output, character in
            if "\\`*_[]#<>".contains(character) { output.append("\\") }
            output.append(character)
        }
    }

    private static func longestBackticks(_ text: String) -> Int {
        text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
    }
}
