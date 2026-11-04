import Foundation

struct FakeTrash: CleanTrashTransport {
    let boundary: URL
    let receipts: URL

    func trash(_ url: URL) throws {
        precondition(url.standardizedFileURL.path.hasPrefix(boundary.standardizedFileURL.path + "/"))
        if url.lastPathComponent == "org.test.failure" { throw CocoaError(.fileWriteNoPermission) }
        try Data(url.path.utf8).write(to: receipts.appendingPathComponent(url.lastPathComponent))
    }
}

@main
struct CleanJunkTest {
    static func main() async throws {
        try await scenario()
        print("PASS: clean scan, safety, revalidation, partial failure and cancellation")
    }

    static func scenario() async throws {
        let manager = FileManager()
        let location = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: location, withIntermediateDirectories: true)
        let temp = location.resolvingSymlinksInPath()
        defer { try? manager.removeItem(at: temp) }
        let home = temp.appendingPathComponent("home")
        let receipts = temp.appendingPathComponent("receipts")
        try manager.createDirectory(at: receipts, withIntermediateDirectories: true)
        let sentinel = temp.appendingPathComponent("sentinel")
        try Data("safe".utf8).write(to: sentinel)
        for category in CleanCategory.allCases {
            try manager.createDirectory(at: home.appendingPathComponent(category.relativeRoot),
                                        withIntermediateDirectories: true)
        }
        let cache = home.appendingPathComponent(CleanCategory.caches.relativeRoot)
        for name in ["org.test.good", "org.test.changed", "org.test.gone", "org.test.failure",
                     "com.apple.keep", "protected"] {
            try Data("cache".utf8).write(to: cache.appendingPathComponent(name))
        }
        try manager.createSymbolicLink(at: cache.appendingPathComponent("escape"),
                                       withDestinationURL: sentinel)
        let nested = cache.appendingPathComponent("org.test.nested")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: nested.appendingPathComponent("escape"),
                                       withDestinationURL: sentinel)
        let old = Date(timeIntervalSinceNow: -200_000)
        for (category, name) in [(CleanCategory.logs, "old.log"), (.logs, "recent.log"),
                                 (.installers, "Install macOS Test.app"), (.firmware, "test.ipsw"),
                                 (.leftovers, "org.test.orphan"), (.leftovers, "org.test.installed"),
                                 (.derivedData, "build"), (.deviceSupport, "device"), (.trash, "keep")] {
            let url = home.appendingPathComponent(category.relativeRoot).appendingPathComponent(name)
            try Data("fixture".utf8).write(to: url)
            if name != "recent.log" {
                try manager.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
            }
        }
        let policy = CleanPolicy(home: home, now: Date(), logAge: 86_400,
                                 installerAge: 86_400, installedBundleIDs: ["org.test.installed"],
                                 protectedNames: ["protected"])
        precondition(!policy.permits(cache.path, category: .caches))
        precondition(!policy.permits(cache.path + "/../Caches/org.test.good", category: .caches))
        precondition(!policy.permits(sentinel.path, category: .caches))
        let service = CleanService(policy: policy,
                                   transport: FakeTrash(boundary: temp, receipts: receipts))
        let items = try await service.scan()
        let initialReceipts = try manager.contentsOfDirectory(atPath: receipts.path)
        precondition(initialReceipts.isEmpty)
        precondition(manager.fileExists(atPath: cache.appendingPathComponent("org.test.good").path))
        precondition(!items.contains { ["escape", "protected", "com.apple.keep"].contains($0.path.lastPathComponent) })
        let excluded = ["org.test.nested", "recent.log", "org.test.installed"]
        precondition(!items.contains { excluded.contains($0.path.lastPathComponent) })
        precondition(Set(items.map(\.category)).count == CleanCategory.allCases.count)
        try Data("changed size".utf8).write(to: cache.appendingPathComponent("org.test.changed"))
        try manager.moveItem(at: cache.appendingPathComponent("org.test.gone"),
                             to: temp.appendingPathComponent("gone"))
        let outcomes = try await service.clean(items)
        precondition(outcomes.contains { $0.item.path.lastPathComponent == "org.test.good" && $0.status == .trashed })
        precondition(outcomes.filter { $0.status == .changedOrMissing }.count == 2,
                     outcomes.map { "\($0.item.path.lastPathComponent): \($0.status)" }.joined(separator: ", "))
        precondition(outcomes.contains { if case .failed = $0.status { true } else { false } })
        precondition(outcomes.allSatisfy { $0.bytesFreed == 0 })
        let sentinelData = try Data(contentsOf: sentinel)
        precondition(sentinelData == Data("safe".utf8))
        let recorded = try manager.contentsOfDirectory(at: receipts, includingPropertiesForKeys: nil)
        precondition(recorded.count == 7)
        for receipt in recorded {
            let path = String(bytes: try Data(contentsOf: receipt), encoding: .utf8)!
            precondition(path.hasPrefix(temp.standardizedFileURL.path + "/"))
        }
        let cancelled = Task {
            try Task.checkCancellation()
            return try await service.scan()
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Expected cancellation")
        } catch is CancellationError {}
    }
}
