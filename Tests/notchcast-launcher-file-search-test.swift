// notchcast-sources: Tinycast/Features/FileSearch/Model/*.swift
// notchcast-sources: Tinycast/Features/FileSearch/Service/FileIndex.swift
// notchcast-sources: Tinycast/Features/FileSearch/Service/FileIndexSnapshot.swift
// notchcast-sources: Tinycast/Features/FileSearch/Service/FileIndexCrawler.swift
import Foundation

@main
struct LauncherFileSearchTests {
    static func main() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "launcher-file-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard let resolved = realpath(scratch.path, nil) else {
            preconditionFailure("Scratch directory must resolve")
        }
        let home = URL(fileURLWithPath: String(cString: resolved)).appending(path: "home")
        free(resolved)
        for path in [
            "Documents/Report.pdf", "Documents/Annual Report.pdf", "Documents/myreport.pdf",
            "Documents/Résumé.txt", "Documents/报告.txt", "Documents/.hidden.txt",
            "Documents/Bundle.app/Contents/info.txt", "Documents/node_modules/dependency.txt",
            "Library/Caches/cache.txt", "Excluded/private.txt", "ExcludedSibling/keep.txt"
        ] {
            try write(home.appending(path: path))
        }
        try write(scratch.appending(path: "outside/outside.txt"))
        try FileManager.default.createSymbolicLink(
            at: home.appending(path: "outside-link"),
            withDestinationURL: scratch.appending(path: "outside"))
        let policy = FileSearchPolicy(
            scopes: ["~", "~/Documents", "~"],
            ignorePatterns: FileSearchIgnoreList.defaults + ["~/Excluded"], homeDirectory: home)
        precondition(policy.roots == [home.standardizedFileURL.path], "Overlapping scopes crawl only once")
        let snapshotURL = scratch.appending(path: "index.bin")
        let snapshot = try build(policy, to: snapshotURL)
        let index = FileIndex()
        index.replace(with: snapshot, policy: policy)

        precondition(names(index, "REPORT").first == "Report.pdf", "Name starts rank first")
        let reports = names(index, "report")
        precondition(
            reports.firstIndex(of: "Annual Report.pdf")! < reports.firstIndex(of: "myreport.pdf")!,
            "Word starts rank ahead of interior matches")
        precondition(names(index, "annual report") == ["Annual Report.pdf"])
        precondition(names(index, "resume") == ["Résumé.txt"], "Accents fold")
        precondition(names(index, "报告") == ["报告.txt"], "Unicode names remain searchable")
        precondition(names(index, "private").isEmpty, "Excluded subtrees never enter the index")
        precondition(names(index, "keep") == ["keep.txt"], "Exclusions respect path boundaries")
        precondition(names(index, "cache").isEmpty && names(index, "dependency").isEmpty)
        precondition(names(index, "outside.txt").isEmpty, "Symlinks never crawl out of scope")
        precondition(names(index, "report", filter: .images).isEmpty)
        precondition(names(index, "documents", filter: .folders) == ["Documents"])
        precondition(FileSearchQuery.prepare(" \n ") == nil)
        precondition(!FileSearchQuery.answersLauncher("ab"))
        precondition(FileSearchQuery.answersLauncher("abc"))
        precondition(snapshot.eventID == 73, "Offline replay starts at the saved event")
        precondition(snapshot.fingerprint == policy.fingerprint)
        precondition(snapshot.lookup(home.path + "/Documents/.hidden.txt") != nil)
        precondition(snapshot.lookup(home.path + "/Documents/Bundle.app/Contents/info.txt") != nil)
        precondition(
            !index.recent(filter: .all).contains { $0.name == ".hidden.txt" || $0.name == "info.txt" },
            "Upstream indexes hidden and package contents but leaves them out of Recent")
        print("Verified launcher-file-search: temp-only crawl, scopes, exclusions, Unicode and ranking")

        try write(home.appending(path: "Documents/Offline.txt"))
        try FileManager.default.moveItem(
            at: home.appending(path: "Documents/Résumé.txt"),
            to: home.appending(path: "Documents/Renamed.txt"))
        guard let reloaded = FileIndexSnapshot(contentsOf: snapshotURL) else {
            preconditionFailure("Saved snapshot must map again")
        }
        let resumed = FileIndex()
        resumed.replace(with: reloaded, policy: policy)
        precondition(names(resumed, "offline").isEmpty)
        resumed.apply(folder: home.appending(path: "Documents").path)
        precondition(names(resumed, "offline") == ["Offline.txt"])
        precondition(names(resumed, "resume").isEmpty)
        precondition(names(resumed, "renamed") == ["Renamed.txt"])
        let count = resumed.itemCount
        let revision = resumed.recentRevision
        resumed.apply(folder: home.appending(path: "Documents").path)
        precondition(resumed.itemCount == count && resumed.recentRevision == revision)
        try FileManager.default.removeItem(at: home.appending(path: "Documents/Offline.txt"))
        resumed.apply(folder: home.appending(path: "Documents").path)
        precondition(names(resumed, "offline").isEmpty)
        let favorites = results(resumed, "report")
        let launcher = FileSearchQuery.launcherResults("report", favorites: favorites, indexed: favorites)
        precondition(Set(launcher.map(\.id)).count == launcher.count)
        precondition(launcher.count <= FileSearchQuery.launcherLimit)
        print("Verified launcher-file-search: snapshot reload, offline relist, rename, delete, replay idempotence")

        let emptyPolicy = FileSearchPolicy(scopes: [], ignorePatterns: [], homeDirectory: home)
        precondition(FileIndexCrawler.roots(of: emptyPolicy).isEmpty)
        let empty = FileIndex()
        empty.replace(with: nil, policy: emptyPolicy)
        precondition(empty.itemCount == 0 && names(empty, "report").isEmpty)
        let corruptURL = scratch.appending(path: "corrupt.bin")
        try Data("invalid index".utf8).write(to: corruptURL)
        precondition(FileIndexSnapshot(contentsOf: corruptURL) == nil)
        print("Verified launcher-file-search: empty scopes, invalid snapshot and launcher deduplication")
    }

    private static func build(_ policy: FileSearchPolicy, to url: URL) throws -> FileIndexSnapshot {
        let roots = FileIndexCrawler.roots(of: policy)
        let listings = FileIndexCrawler.Crawl(roots: roots, policy: policy).run(workers: 2)
        try FileIndexSnapshot.write(
            listings, roots: roots, eventID: 73, fingerprint: policy.fingerprint, to: url)
        guard let snapshot = FileIndexSnapshot(contentsOf: url) else {
            preconditionFailure("Fixture index must map")
        }
        return snapshot
    }

    private static func results(_ index: FileIndex, _ query: String) -> [FileSearchResult] {
        index.search(FileSearchQuery.prepare(query)!, filter: .all)
    }

    private static func names(
        _ index: FileIndex, _ query: String, filter: FileSearchFilter = .all
    ) -> [String] {
        index.search(FileSearchQuery.prepare(query)!, filter: filter).map(\.name)
    }

    private static func write(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
    }
}
