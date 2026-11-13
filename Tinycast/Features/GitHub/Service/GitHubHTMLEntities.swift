import Foundation

enum GitHubHTMLEntities {
    private static let named: [String: String] = [
        "amp;": "&",
        "lt;": "<",
        "gt;": ">",
        "quot;": "\"",
        "apos;": "'",
        "nbsp;": "\u{00a0}",
    ]

    static func decode(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&" else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            let start = text.index(after: index)
            let limit = text.index(start, offsetBy: 33, limitedBy: text.endIndex) ?? text.endIndex
            var end = limit
            var decoded: String?
            while end > start {
                let key = String(text[start..<end])
                decoded = named[key]
                if key.hasPrefix("#"), key.hasSuffix(";") {
                    let digits = key.dropFirst().dropLast()
                    let hex = digits.first == "x" || digits.first == "X"
                    if let value = UInt32(hex ? String(digits.dropFirst()) : String(digits), radix: hex ? 16 : 10),
                        let scalar = UnicodeScalar(value) {
                        decoded = String(scalar)
                    }
                }
                if decoded != nil { break }
                end = text.index(before: end)
            }
            if let decoded {
                result += decoded
                index = end
            } else {
                result.append("&")
                index = start
            }
        }
        return result
    }
}
