import Foundation

struct AppUpdatesChecker: Sendable {
    var fetch: @Sendable (URL) async throws -> Data
    var outdated: @Sendable () async throws -> Data
    var width = 4

    struct Snapshot: Sendable {
        let checkedAt: Date
        let results: [AppUpdate]
    }

    func check(apps: [AppUpdate.App], now: Date) async throws -> Snapshot {
        var casks: [String: String] = [:]
        var brewAvailable = false
        if apps.contains(where: { $0.cask != nil }) {
            do {
                let data = try await outdated()
                guard data.count <= AppUpdateFeed.limit else { throw URLError(.dataLengthExceedsMaximum) }
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                brewAvailable = root?["casks"] is [[String: Any]]
                for row in root?["casks"] as? [[String: Any]] ?? [] {
                    if let name = row["name"] as? String, let version = row["current_version"] as? String {
                        casks[name] = version
                    }
                }
            } catch is CancellationError { throw CancellationError() } catch { casks = [:] }
        }
        let versions = casks
        let hasBrewResults = brewAvailable
        let results = try await withThrowingTaskGroup(of: (Int, AppUpdate).self) { group in
            var next = 0
            var rows: [(Int, AppUpdate)] = []
            func add() {
                guard next < apps.count else { return }
                let index = next
                next += 1
                group.addTask { (index, try await self.check(apps[index], casks: versions,
                                                           brewAvailable: hasBrewResults)) }
            }
            for _ in 0..<min(max(1, width), 8) { add() }
            while let row = try await group.next() {
                try Task.checkCancellation()
                rows.append(row)
                add()
            }
            return rows.sorted { $0.0 < $1.0 }.map(\.1)
        }
        try Task.checkCancellation()
        return Snapshot(checkedAt: now, results: results)
    }

    private func check(_ app: AppUpdate.App, casks: [String: String],
                       brewAvailable: Bool) async throws -> AppUpdate {
        try Task.checkCancellation()
        var source: AppUpdate.Source?
        do {
            var latest: String
            var comparison: ComparisonResult?
            var link: URL?
            if app.appStore {
                source = .appStore
                var url = URLComponents(string: "https://itunes.apple.com/lookup")!
                url.queryItems = [URLQueryItem(name: "bundleId", value: app.id),
                                  URLQueryItem(name: "entity", value: "macSoftware")]
                let data = try await fetch(url.url!)
                guard data.count <= AppUpdateFeed.limit else { throw URLError(.dataLengthExceedsMaximum) }
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let row = (root?["results"] as? [[String: Any]])?.first(where: {
                    $0["bundleId"] as? String == app.id
                }), let version = row["version"] as? String else { throw URLError(.cannotParseResponse) }
                latest = version
                comparison = AppUpdateVersion.compare(app.version, latest)
                link = (row["trackViewUrl"] as? String).flatMap(URL.init(string:))
            } else if let token = app.cask {
                source = .homebrew
                guard brewAvailable else { throw URLError(.resourceUnavailable) }
                let version = casks[token] ?? app.version
                latest = version
                comparison = AppUpdateVersion.compare(app.version, latest)
                link = URL(string: "https://formulae.brew.sh/cask/")?.appendingPathComponent(token)
            } else if let feed = app.feed {
                source = .sparkle
                guard feed.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
                let releases = try AppUpdateFeed.releases(try await fetch(feed))
                guard let best = releases.max(by: {
                    AppUpdateVersion.compare($0.build, $1.build) == .orderedAscending
                }), releases.allSatisfy({ AppUpdateVersion.compare($0.build, best.build) != nil }) else {
                    throw URLError(.cannotParseResponse)
                }
                latest = best.version
                comparison = AppUpdateVersion.compare(app.build, best.build)
                link = feed
            } else {
                return AppUpdate(app: app, source: nil, latest: nil, link: nil, isNewer: nil)
            }
            try Task.checkCancellation()
            return AppUpdate(app: app, source: source, latest: latest,
                             link: link?.scheme == "https" ? link : nil,
                             isNewer: comparison.map { $0 == .orderedAscending })
        } catch is CancellationError { throw CancellationError() } catch {
            try Task.checkCancellation()
            return AppUpdate(app: app, source: source, latest: nil, link: nil, isNewer: nil)
        }
    }
}
