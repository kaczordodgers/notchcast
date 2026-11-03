import Foundation

struct WebpageArticle: Sendable {
    let title: String
    let author: String
    let published: String?
    let source: URL
    let baseURL: URL
    let html: String

    func markdown(saved: Date) -> String {
        let date = saved.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let body = HTMLMarkdown.convert(html, baseURL: baseURL)
        let escapedTitle = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let heading = "# " + HTMLMarkdown.convert("<span>\(escapedTitle)</span>", baseURL: baseURL)
        var lines = ["---", "title: \(Self.quoted(title))", "author: \(Self.quoted(author))",
                     "source: \(Self.quoted(source.absoluteString))"]
        if let published, let day = Self.publicationDay(published) { lines.append("published: \(day)") }
        lines += ["saved: \(date)", "type: article", "---", ""]
        if body.components(separatedBy: "\n").first != heading { lines += [heading, ""] }
        lines += [body, ""]
        return lines.joined(separator: "\n")
    }

    var filename: String {
        let name = "\(author) - \(title)".replacingOccurrences(of: "[/\\\\:*?\"<>|\\p{Cc}]+", with: " ",
                                                           options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var result = ""
        for character in name {
            guard result.utf8.count + String(character).utf8.count <= 200 else { break }
            result.append(character)
        }
        return result.isEmpty ? "article" : result
    }

    private static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(text), let value = String(data: data, encoding: .utf8) else { return "\"\"" }
        return value
    }

    private static func publicationDay(_ text: String) -> String? {
        let prefix = String(text.prefix(10))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: prefix), formatter.string(from: date) == prefix else { return nil }
        return prefix
    }
}
