// notchcast-sources: Tinycast/Features/AppUpdates/Model/*.swift Tinycast/Features/AppUpdates/Service/*.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation

@main
struct AppUpdatesTest {
    static func main() async throws {
        for (left, right, expected) in [
            ("1.2", "1.2.0", ComparisonResult.orderedSame),
            ("1.9", "1.10", .orderedAscending),
            ("2026.100", "2026.99", .orderedDescending),
            ("001", "1", .orderedSame)
        ] {
            precondition(AppUpdateVersion.compare(left, right) == expected)
        }
        for value in ["1.2beta", "1.2 (42)", "", "latest", "1..2", "18446744073709551616"] {
            precondition(AppUpdateVersion.compare(value, "2") == nil)
        }
        let feed = Data("""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel><item><enclosure sparkle:version="20" sparkle:shortVersionString="2"/>
        </item></channel></rss>
        """.utf8)
        let checker = AppUpdatesChecker(fetch: { url in
            switch url.lastPathComponent {
            case "good": return feed
            case "large": return Data(repeating: 32, count: AppUpdateFeed.limit + 1)
            case "broken": return Data("<rss><item>".utf8)
            case "failure": throw URLError(.notConnectedToInternet)
            default: preconditionFailure("Refused URL reached transport")
            }
        }, outdated: { Data("{\"casks\":[]}".utf8) })
        let apps = ["broken", "large", "failure", "good"].map {
            AppUpdate.App(id: $0, version: "1", build: "10", feed: URL(string: "https://fixture.invalid/" + $0))
        } + [AppUpdate.App(id: "http", version: "1", build: "10",
                          feed: URL(string: "http://fixture.invalid/refused"))]
        let snapshot = try await checker.check(apps: apps, now: Date(timeIntervalSince1970: 0))
        precondition(snapshot.results.count == 5)
        precondition(snapshot.results[3].isNewer == true)
        for index in [0, 1, 2, 4] { precondition(snapshot.results[index].isNewer == nil) }
        let cancelled = Task {
            try Task.checkCancellation()
            return try await checker.check(apps: apps, now: Date(timeIntervalSince1970: 0))
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancellation lost") } catch is CancellationError {}
        print("PASS: version table; malformed/oversized unknown; failure isolated; HTTP refused; cancellation")
    }
}
