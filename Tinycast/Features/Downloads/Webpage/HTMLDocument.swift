import Foundation

struct HTMLDocument {
    struct Node {
        var tag: String
        var attributes: [String: String] = [:]
        var text = ""
        var children: [Node] = []

        var plainText: String { tag == "#text" ? text : children.map(\.plainText).joined() }

        func descendants(tag: String) -> [Node] {
            children.flatMap { $0.tag == tag ? [$0] : $0.descendants(tag: tag) }
        }
    }

    static let dropped: Set<String> = [
        "script", "style", "nav", "footer", "aside", "noscript", "iframe", "form", "button", "svg",
        "head", "template", "dialog", "canvas", "video", "audio", "input", "select", "textarea"
    ]
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]
    let root: Node

    init(_ html: String) {
        let scanner = Scanner(string: html)
        scanner.charactersToBeSkipped = nil
        var stack = [Node(tag: "#root")]
        while !scanner.isAtEnd {
            if let text = scanner.scanUpToString("<"), !text.isEmpty {
                stack[stack.count - 1].children.append(Node(tag: "#text", text: Self.decode(text)))
            }
            guard scanner.scanString("<") != nil else { break }
            if scanner.scanString("!--") != nil {
                _ = scanner.scanUpToString("-->")
                _ = scanner.scanString("-->")
                continue
            }
            let closing = scanner.scanString("/") != nil
            guard let name = scanner.scanCharacters(from: .alphanumerics), !name.isEmpty else {
                if scanner.scanString("!") != nil || scanner.scanString("?") != nil {
                    _ = scanner.scanUpToString(">")
                    _ = scanner.scanString(">")
                } else {
                    stack[stack.count - 1].children.append(Node(tag: "#text", text: "<"))
                }
                continue
            }
            let tag = name.lowercased()
            if closing {
                _ = scanner.scanUpToString(">")
                _ = scanner.scanString(">")
                if let index = stack.lastIndex(where: { $0.tag == tag }), index > 0 {
                    while stack.count > index { Self.close(&stack) }
                }
                continue
            }
            var attributes: [String: String] = [:]
            var selfClosing = false
            while !scanner.isAtEnd {
                _ = scanner.scanCharacters(from: .whitespacesAndNewlines)
                if scanner.scanString("/>") != nil { selfClosing = true; break }
                if scanner.scanString(">") != nil { break }
                let keyCharacters = CharacterSet(charactersIn: " \t\r\n=/><").inverted
                guard let key = scanner.scanCharacters(from: keyCharacters) else {
                    scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
                    continue
                }
                _ = scanner.scanCharacters(from: .whitespacesAndNewlines)
                var value = ""
                if scanner.scanString("=") != nil {
                    _ = scanner.scanCharacters(from: .whitespacesAndNewlines)
                    let quote = scanner.scanString("\"") ?? scanner.scanString("'")
                    if let quote {
                        value = scanner.scanUpToString(quote) ?? ""
                        _ = scanner.scanString(quote)
                    } else {
                        value = scanner.scanCharacters(from: CharacterSet(charactersIn: " \t\r\n>").inverted) ?? ""
                    }
                }
                attributes[key.lowercased()] = Self.decode(value)
            }
            if ["script", "style", "textarea", "title"].contains(tag) {
                let remaining = scanner.string[scanner.currentIndex...]
                if let end = remaining.range(of: "</\(tag)", options: .caseInsensitive) {
                    let text = String(remaining[..<end.lowerBound])
                    let node = Node(tag: tag, children: [Node(tag: "#text", text: Self.decode(text))])
                    stack[stack.count - 1].children.append(node)
                    scanner.currentIndex = end.lowerBound
                    continue
                }
                break
            }
            if ["p", "li", "tr", "td", "th"].contains(tag), stack.last?.tag == tag { Self.close(&stack) }
            let node = Node(tag: tag, attributes: attributes)
            if selfClosing || Self.voidTags.contains(tag) || stack.count >= 128 {
                stack[stack.count - 1].children.append(node)
            } else {
                stack.append(node)
            }
        }
        while stack.count > 1 { Self.close(&stack) }
        root = stack[0]
    }

    private static func close(_ stack: inout [Node]) {
        let node = stack.removeLast()
        stack[stack.count - 1].children.append(node)
    }

    private static func decode(_ text: String) -> String {
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                        "copy": "©", "reg": "®", "hellip": "…", "mdash": "—", "ndash": "–",
                        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•", "trade": "™"]
        guard let expression = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);") else { return text }
        var result = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange])
            var value = entities[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let number = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) {
                    value = String(scalar)
                }
            }
            if let value { result.replaceSubrange(whole, with: value) }
        }
        return result
    }
}
