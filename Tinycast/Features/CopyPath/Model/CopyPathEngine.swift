import Foundation

enum CopyPathEngine {
    enum Outcome: Equatable, Sendable {
        case path(String)
        case link(String)
        case nothing
    }

    static func paths(_ paths: [String], home: String) -> Outcome {
        let text = paths.filter { $0.hasPrefix("/") }.map { display($0, home: home) }
        return text.isEmpty ? .nothing : .path(text.joined(separator: "\n"))
    }

    static func document(_ address: String?, home: String) -> Outcome {
        guard let address, !address.isEmpty else { return .nothing }
        if address.hasPrefix("/") { return paths([address], home: home) }
        if let url = URL(string: address), url.isFileURL, url.host == nil || url.host == "localhost" {
            return paths([url.path(percentEncoded: false)], home: home)
        }
        return cleanLink(address).map(Outcome.link) ?? .nothing
    }

    static func cleanLink(_ address: String) -> String? {
        guard var parts = URLComponents(string: address),
            ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
            let host = parts.host, !host.isEmpty else { return nil }
        guard let items = parts.percentEncodedQueryItems else { return address }
        let kept = items.filter { item in
            let name = (item.name.removingPercentEncoding ?? item.name).lowercased()
            return !name.hasPrefix("utm_") && !tracking.contains(name)
        }
        guard kept.count != items.count else { return address }
        parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return parts.string
    }

    private static let tracking: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "mc_cid", "mc_eid", "_ga", "_gl", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "ref_src"
    ]

    private static func display(_ raw: String, home: String) -> String {
        var path = raw
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
