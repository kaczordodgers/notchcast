import Foundation

nonisolated enum URLCleanerPolicy {
    struct Rules: Codable, Equatable, Sendable {
        var custom: [String] = []
        var perSite: [String: [String]] = [:]
        var disabled: [String] = []
    }

    struct Result: Equatable, Sendable {
        let text: String
        let removed: [String]
    }

    static func clean(_ text: String, rules: Rules = Rules()) -> Result {
        let unchanged = Result(text: text, removed: [])
        guard !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              let url = URLComponents(string: text),
              WebRules.isWebScheme(url.scheme),
              let host = url.host?.lowercased(), !host.isEmpty,
              let question = text.firstIndex(of: "?") else { return unchanged }
        let fragment = text.firstIndex(of: "#") ?? text.endIndex
        guard question < fragment else { return unchanged }
        let pairs = text[text.index(after: question)..<fragment].split(separator: "&", omittingEmptySubsequences: false)
        var removed: [String] = []
        let kept = pairs.filter { pair in
            let rawName = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]
            guard let name = String(rawName).removingPercentEncoding?.lowercased() else { return true }
            let disabled = rules.disabled.contains { $0.lowercased() == name }
            let custom = (rules.custom + (rules.perSite[host] ?? [])).contains { $0.lowercased() == name }
            guard !disabled, custom || WebRules.isTrackingParameter(name) else { return true }
            removed.append(String(pair))
            return false
        }
        guard !removed.isEmpty else { return unchanged }
        let query = kept.isEmpty ? "" : "?" + kept.joined(separator: "&")
        return Result(text: String(text[..<question]) + query + text[fragment...], removed: removed)
    }
}
