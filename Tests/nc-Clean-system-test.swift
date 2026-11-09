import Foundation

@main
struct CleanSystemTest {
    static func main() throws {
        let manager = FileManager()
        let temp = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temp) }
        let sentinel = temp.appendingPathComponent("sentinel")
        try Data("safe".utf8).write(to: sentinel)
        let rules: [CleanSystemPolicy.Rule] = [.caches, .rotatedLogs, .diagnosticReports, .unifiedLog]
        let roots = try rules.enumerated().map { index, rule in
            let url = temp.appendingPathComponent("root-\(index)")
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            return CleanSystemPolicy.Root(path: url.path, rule: rule)
        }
        let now = Date(timeIntervalSince1970: 2_000_000)
        let policy = CleanSystemPolicy(roots: roots, now: now, cacheAge: 100, logAge: 100)
        func entry(_ root: Int, _ name: String, young: Bool = false,
                   symlink: Bool = false) -> CleanSystemEntry {
            CleanSystemEntry(path: roots[root].path + "/" + name, size: 12,
                             modified: now.addingTimeInterval(young ? -10 : -200),
                             identity: name, isRegularFile: true, hasSymlinkComponent: symlink)
        }
        let eligible = [entry(0, "cache"), entry(1, "system.log.1"), entry(1, "system.log.gz")]
            + ["ips", "crash", "diag", "spin", "hang", "panic", "shutdownstall", "gpurestart"]
                .map { entry(2, "report." + $0) }
            + ["persist", "special", "signpost", "highvolume"].map { entry(3, $0 + "/old.tracev3") }
        let kept = [entry(1, "system.log"), entry(1, "install.log"), entry(0, "young", young: true),
                    entry(1, "young.log.gz", young: true), entry(2, "unknown.txt"),
                    entry(3, "other/old.tracev3"), entry(3, "old.tracev3"),
                    entry(1, "a/b/c/old.log.gz"), entry(2, "a/b/report.ips")]
        let unsafe = [entry(0, "link", symlink: true), entry(0, "link/child", symlink: true),
                      entry(0, "../sentinel"), entry(0, "sub/../cache"),
                      CleanSystemEntry(path: sentinel.path, size: 4, modified: .distantPast,
                                       identity: "outside", isRegularFile: true, hasSymlinkComponent: false),
                      CleanSystemEntry(path: roots[0].path, size: 0, modified: .distantPast,
                                       identity: "root", isRegularFile: true, hasSymlinkComponent: false)]
        for item in eligible { precondition(policy.reason(for: item) != nil) }
        for item in kept + unsafe { precondition(policy.reason(for: item) == nil) }
        print("PASS: classification, ages and path safety")
    }
}
