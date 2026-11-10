import Foundation

enum NotchcastLink {
    static func clean(_ address: String) -> String? {
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
}
