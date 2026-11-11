import Foundation

nonisolated struct AIUsageProvider: Sendable {
    let cacheDirectory: URL
    var staleAfter: TimeInterval = OtherMacUsageSnapshot.staleAfter
    var clock: @Sendable () -> Date = { Date() }

    static func cacheDirectory(path: String, homeDirectory: URL) -> URL {
        path.isEmpty ? AgentPaths(home: homeDirectory).t3Caches : URL(fileURLWithPath: path)
    }

    @concurrent
    func refresh() async -> [AIUsageSnapshot] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            let missing = (error as NSError).code == NSFileReadNoSuchFileError
            return [AIUsageSnapshot(providerID: "", plan: nil, checkedAt: nil,
                                    status: missing ? .noData : .unreadable, windows: [])]
        }
        let now = clock()
        return files.map { file in
            let id = file.deletingPathExtension().lastPathComponent
            do {
                return try AIUsageParser.parse(Data(contentsOf: file), providerID: id,
                                               now: now, staleAfter: staleAfter)
            } catch {
                return AIUsageSnapshot(providerID: id, plan: nil, checkedAt: nil,
                                       status: .unreadable, windows: [])
            }
        }
    }
}
