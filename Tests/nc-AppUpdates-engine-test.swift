// notchcast-sources: Tinycast/Features/AppUpdates/Model/*.swift Tinycast/Features/AppUpdates/Service/*.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation

@main
struct AppUpdatesTest {
    static func main() async throws {
        let system = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        for (metadata, fits) in [
            ("<sparkle:minimumSystemVersion>26.1</sparkle:minimumSystemVersion>", true),
            ("<sparkle:minimumSystemVersion>26.2</sparkle:minimumSystemVersion>", false),
            ("<sparkle:maximumSystemVersion>26.1</sparkle:maximumSystemVersion>", true),
            ("<sparkle:maximumSystemVersion>26.0</sparkle:maximumSystemVersion>", false),
            ("<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>", true),
            ("<sparkle:hardwareRequirements>x86_64</sparkle:hardwareRequirements>", false),
            ("<sparkle:hardwareRequirements>x86_64, arm64</sparkle:hardwareRequirements>", true)
        ] {
            let fixture = Data("""
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
            <sparkle:version>20</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
            \(metadata)
            <enclosure url="https://fixture.invalid/App.zip" length="12345" type="application/octet-stream"/>
            <sparkle:deltas><enclosure url="https://fixture.invalid/App.delta" sparkle:deltaFrom="19"
            sparkle:version="20" length="123" type="application/octet-stream"/></sparkle:deltas>
            </item></channel></rss>
            """.utf8)
            let releases = try AppUpdateFeed.releases(fixture, systemVersion: system, architecture: "arm64")
            precondition(releases.count == (fits ? 1 : 0))
            if fits { precondition(releases.first?.build == "20" && releases.first?.version == "2.0") }
        }
        for body in [
            "<enclosure sparkle:version=\"20\"/><sparkle:minimumSystemVersion>26</sparkle:minimumSystemVersion>",
            "<enclosure/><sparkle:version>20</sparkle:version>",
            "<enclosure sparkle:version=\"20\"/>"
        ] {
            let fixture = Data("<rss xmlns:sparkle=\"urn:sparkle\"><channel><item>\(body)</item></channel></rss>".utf8)
            let releases = try AppUpdateFeed.releases(fixture)
            precondition(releases.first?.build == "20")
        }
        for (left, right, expected) in [
            ("1.2", "1.2.0", ComparisonResult.orderedSame),
            ("1.9", "1.10", .orderedAscending),
            ("2026.100", "2026.99", .orderedDescending),
            ("001", "1", .orderedSame)
        ] {
            precondition(AppUpdateVersion.compare(left, right) == expected)
        }
        let caskData = Data(#"{"casks":[{"token":"fixture","artifacts":[{"app":["Fixture.app"]}]}]}"#.utf8)
        precondition(AppUpdateFeed.caskApplications(caskData)["Fixture.app"] == "fixture")
        let brewChecker = AppUpdatesChecker(fetch: { _ in preconditionFailure("Unexpected fetch") },
            outdated: { Data(#"{"casks":[{"name":"fixture","current_version":"2"}]}"#.utf8) })
        let brewRows = try await brewChecker.check(apps: [
            .init(id: "new", version: "1", build: "1", cask: "fixture"),
            .init(id: "current", version: "1", build: "1", cask: "current")
        ], now: Date(timeIntervalSince1970: 0)).results
        precondition(brewRows.map(\.isNewer) == [true, false])
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
        print("PASS: version table; malformed/oversized unknown; failure isolated; HTTP refused")
    }
}
