import Foundation

nonisolated enum LinkCleaner {
    private static let youtubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com"]
    private static let xHosts: Set<String> = ["x.com", "twitter.com", "mobile.twitter.com"]
    private static let tail = #"(?:[^\s<>"'`()\]]|\([^\s<>"'`()]*\))"#
    private static let pattern = try? NSRegularExpression(
        pattern: #"(?:https?://|www\.)\#(tail)+|[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/\#(tail)*"#,
        options: [.caseInsensitive])

    static func links(in text: String) -> [String] {
        var seen = Set<String>()
        return (pattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).compactMap { match in
            guard let range = Range(match.range, in: text), !text[..<range.lowerBound].hasSuffix("://"),
                let link = clean(String(text[range])), seen.insert(key(link)).inserted else { return nil }
            return link
        }
    }

    static func clean(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".,;:!?".contains(last) { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://"), !text.lowercased().hasPrefix("https://") {
            guard !text.contains("://") else { return nil }
            text = "https://" + text
        }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
            WebRules.isWebScheme(scheme), let host = parts.host?.lowercased(), host.contains("."),
            !host.hasPrefix("."), !host.hasSuffix("."), parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = scheme
        parts.host = host
        parts.fragment = nil
        if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) { parts.port = nil }
        var items = (parts.queryItems ?? []).filter { !WebRules.isTrackingParameter($0.name) }
        if host == "youtu.be" {
            guard let id = parts.path.split(separator: "/").first else { return nil }
            return youtube(String(id))
        }
        if youtubeHosts.contains(host) {
            parts.scheme = "https"
            parts.host = "www.youtube.com"
            if parts.path == "/watch" {
                guard let id = items.first(where: { $0.name == "v" })?.value, !id.isEmpty else { return nil }
                return youtube(id)
            }
            for prefix in ["/shorts/", "/live/", "/embed/"] where parts.path.hasPrefix(prefix) {
                guard let id = parts.path.dropFirst(prefix.count).split(separator: "/").first else { return nil }
                return youtube(String(id))
            }
            items.removeAll { ["si", "feature", "pp"].contains($0.name.lowercased()) }
            if parts.path == "/playlist" { items.removeAll { $0.name != "list" } }
        }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if xHosts.contains(bareHost) { items.removeAll { ["s", "t"].contains($0.name) } }
        parts.queryItems = items.isEmpty ? nil : items
        if parts.path.hasSuffix("/") { parts.path.removeLast() }
        return parts.string
    }

    static func key(_ canonical: String) -> String {
        guard var parts = URLComponents(string: canonical), let host = parts.host?.lowercased() else { return canonical }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        parts.host = xHosts.contains(bareHost) ? "x.com" : bareHost
        parts.scheme = "https"
        return parts.string ?? canonical
    }

    private static func youtube(_ id: String) -> String? {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }) else {
            return nil
        }
        return "https://www.youtube.com/watch?v=\(id)"
    }
}
