import Foundation

nonisolated struct AIUsageProvider: Sendable {
    let cacheDirectory: URL
    var staleAfter: TimeInterval = OtherMacUsageSnapshot.staleAfter
    var clock: @Sendable () -> Date = { Date() }

    static func cacheDirectory(path: String, homeDirectory: URL) -> URL {
        path.isEmpty ? AgentPaths(home: homeDirectory).t3Caches : URL(fileURLWithPath: path)
    }

    @concurrent
    static func fetch(gateway: String, now: Date) async throws -> [AIUsageSnapshot] {
        guard let base = URL(string: gateway), ["http", "https"].contains(base.scheme),
              base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else { throw URLError(.badURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: base.appending(path: "v1/magpie/quotas"))
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()
        return try MagpieQuotaDecoder.decode(data, now: now)
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
