import Foundation

nonisolated enum WebRules {
    static func isWebScheme(_ scheme: String?) -> Bool { ["http", "https"].contains(scheme?.lowercased() ?? "") }

    static func isLoopbackHost(_ host: String?) -> Bool { ["127.0.0.1", "localhost", "::1"].contains(host?.lowercased() ?? "") }

    static func isTrackingParameter(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }

    static func cleanLink(_ address: String) -> String? {
        guard var parts = URLComponents(string: address),
            isWebScheme(parts.scheme),
            let host = parts.host, !host.isEmpty else { return nil }
        guard let items = parts.percentEncodedQueryItems else { return address }
        let kept = items.filter { !isTrackingParameter($0.name.removingPercentEncoding ?? $0.name) }
        guard kept.count != items.count else { return address }
        parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return parts.string
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// 0 on success, else errno; `onlyIfMissing` leaves a flag macOS or another app already set.
    static func stampQuarantine(_ path: String, onlyIfMissing: Bool = false, now: Date = Date()) -> Int32 {
        if onlyIfMissing, getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 { return 0 }
        let value = "0083;\(String(Int(now.timeIntervalSince1970), radix: 16));Notchcast;"
        let result = value.withCString { setxattr(path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        return result == 0 ? 0 : errno
    }

    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "igshid", "igsh",
        "mc_cid", "mc_eid", "_ga", "_gl", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "ref_src", "ref_url", "spm"
    ]
}
