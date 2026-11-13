import Foundation

struct URLCleanerRulesDraft {
    var custom = ""
    var disabled = ""
    var sites = ""

    init() {}

    init(_ rules: URLCleanerPolicy.Rules) {
        custom = rules.custom.joined(separator: ",")
        disabled = rules.disabled.joined(separator: ",")
        sites = rules.perSite.sorted { $0.key < $1.key }
            .map { $0.key + "=" + $0.value.joined(separator: ",") }.joined(separator: ";")
    }

    var rules: URLCleanerPolicy.Rules {
        var perSite: [String: [String]] = [:]
        for row in sites.split(separator: ";") {
            let parts = row.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            perSite[String(parts[0]).lowercased()] = parts.count == 2 ? Self.list(String(parts[1])) : []
        }
        return URLCleanerPolicy.Rules(custom: Self.list(custom), perSite: perSite, disabled: Self.list(disabled))
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}
