import Foundation

struct CleanSystemPolicy: Sendable {
    enum Rule: Sendable { case caches, rotatedLogs, diagnosticReports, unifiedLog }

    struct Root: Sendable {
        let path: String
        let rule: Rule
    }

    static let allowedRoots: [Root] = [
        Root(path: "/Library/Caches", rule: .caches),
        Root(path: "/Library/Logs", rule: .rotatedLogs),
        Root(path: "/private/var/log", rule: .rotatedLogs),
        Root(path: "/Library/Logs/DiagnosticReports", rule: .diagnosticReports),
        Root(path: "/private/var/db/diagnostics", rule: .unifiedLog),
    ]

    let roots: [Root]
    let now: Date
    let cacheAge: TimeInterval
    let logAge: TimeInterval

    func reason(for entry: CleanSystemEntry) -> CleanSystemPlan.Reason? {
        let path = entry.path
        guard !path.utf8.contains(0), path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              !path.split(separator: "/").contains("."), !entry.hasSymlinkComponent,
              entry.isRegularFile, entry.size >= 0,
              "/" + path.split(separator: "/").joined(separator: "/") == path,
              let root = roots.sorted(by: { $0.path.count > $1.path.count }).first(where: {
                  path == $0.path || path.hasPrefix($0.path + "/")
              }), path != root.path else { return nil }
        let relative = path.dropFirst(root.path.count + 1).split(separator: "/").map(String.init)
        let name = relative.last!.lowercased()
        let age = now.timeIntervalSince(entry.modified)
        guard age > max(0, root.rule == .caches ? cacheAge : logAge) else { return nil }
        switch root.rule {
        case .caches:
            return .agedCache
        case .rotatedLogs:
            guard relative.count <= 3, name != "install.log" else { return nil }
            let parts = name.split(separator: ".")
            let numbered = parts.count >= 3 && parts[parts.count - 2] == "log"
                && parts.last!.allSatisfy(\.isNumber)
            guard numbered || [".gz", ".bz2", ".xz"].contains(where: name.hasSuffix) else { return nil }
            return .rotatedLog
        case .diagnosticReports:
            guard relative.count <= 2,
                  ["ips", "crash", "diag", "spin", "hang", "panic", "shutdownstall", "gpurestart"]
                    .contains((name as NSString).pathExtension) else { return nil }
            return .diagnosticReport
        case .unifiedLog:
            guard relative.count == 2,
                  ["persist", "special", "signpost", "highvolume"].contains(relative[0].lowercased()),
                  name.hasSuffix(".tracev3") else { return nil }
            return .unifiedLog
        }
    }
}
