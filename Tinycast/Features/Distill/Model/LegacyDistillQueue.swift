import Foundation

nonisolated enum LegacyDistillQueue {
    static func parse(_ data: Data, now: Date) throws -> [DistillLink] {
        let root = try JSONSerialization.jsonObject(with: data)
        let entries: [Any]
        if let list = root as? [Any] {
            entries = list
        } else if let object = root as? [String: Any] {
            if let list = object["entries"] as? [Any] {
                entries = list
            } else if let keyed = object["entries"] as? [String: Any] {
                entries = keyed.sorted { $0.key < $1.key }.map { key, value in
                    var entry = (value as? [String: Any]) ?? [:]
                    if entry["url"] == nil { entry["url"] = key }
                    return entry
                }
            } else { throw CocoaError(.coderReadCorrupt) }
        } else { throw CocoaError(.coderReadCorrupt) }
        var seen = Set<String>()
        return entries.compactMap { entry -> DistillLink? in
            let object = (entry as? [String: Any]) ?? [:]
            let raw = (entry as? String)
                ?? string(object, keys: ["url", "canonicalUrl", "canonicalURL", "canonical", "link", "href"])
            guard let raw, let url = LinkCleaner.clean(raw) else { return nil }
            let state = string(object, keys: ["state", "status", "stage"])?.lowercased() ?? "queued"
            let failed = ["failed", "error"].contains(state)
            guard failed || ["queued", "pending", "waiting"].contains(state),
                seen.insert(LinkCleaner.key(url)).inserted else { return nil }
            let added = ["addedAt", "added", "addedDate", "dateAdded", "createdAt", "queuedAt"]
                .lazy.compactMap { date(object[$0]) }.first ?? now
            let attempts = ["attempts", "attemptCount", "tries"].lazy.compactMap { object[$0] as? Int }.first ?? 0
            return DistillLink(
                url: url, added: added, state: failed ? .failed : .waiting,
                detail: failed ? string(object, keys: ["lastError", "error", "reason", "message"]) : nil,
                attempts: max(0, attempts))
        }.enumerated().sorted { ($0.element.added, $0.offset) < ($1.element.added, $1.offset) }.map(\.element)
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        keys.lazy.compactMap { object[$0] as? String }.first
    }

    private static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        guard let number = value as? Double, number.isFinite, number > 0 else { return nil }
        if number > 100_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
        if number > 1_200_000_000 { return Date(timeIntervalSince1970: number) }
        return Date(timeIntervalSinceReferenceDate: number)
    }
}
