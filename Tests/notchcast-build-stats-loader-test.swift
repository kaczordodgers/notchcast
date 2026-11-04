// notchcast-sources: Tinycast/Features/BuildStats/Model/BuildStatsSnapshot.swift
// notchcast-sources: Tinycast/Features/BuildStats/Service/BuildStatsLoader.swift
import Foundation

@main
struct BuildStatsLoaderTest {
    static func main() async throws {
        let fixture = "Tests/fixtures/build-stats-v1.json"
        guard case let .loaded(model) = await BuildStatsLoader.load(path: fixture) else {
            fatalError("fixture must load")
        }
        precondition(model.byModel["model-a"]?.input == 1200)
        precondition(model.byEffort["high"]?.output == 200)
        precondition(model.timeline.count == 2 && model.latestChangelog.count == 1)
        precondition(model.metrics["checksPassed"] == 12 && model.entryCount == 5)
        let empty = await BuildStatsLoader.load(path: "")
        let missing = await BuildStatsLoader.load(path: fixture + ".missing")
        precondition(empty == .unconfigured)
        precondition(missing == .failed(.missing))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("snapshot.json")
        let fixtureText = try String(contentsOfFile: fixture, encoding: .utf8)
        let combined = fixtureText.replacingOccurrences(of: "model-b", with: "model-a")
        try Data(combined.utf8).write(to: file)
        guard case let .loaded(aggregate) = await BuildStatsLoader.load(path: file.path) else {
            fatalError("groups must aggregate")
        }
        precondition(aggregate.byModel["model-a"]?.input == 2000)
        let overflowing = combined.replacingOccurrences(of: "1200", with: String(Int64.max))
        try Data(overflowing.utf8).write(to: file)
        let overflow = await BuildStatsLoader.load(path: file.path)
        precondition(overflow == .failed(.overflow))
        try Data("{}".utf8).write(to: file)
        let invalid = await BuildStatsLoader.load(path: file.path)
        precondition(invalid == .failed(.invalid))
        try Data(repeating: 32, count: BuildStatsSnapshot.maximumBytes + 1).write(to: file)
        let large = await BuildStatsLoader.load(path: file.path)
        precondition(large == .failed(.tooLarge))
        print("PASS: fixture aggregation, overflow, unconfigured, missing, invalid, oversized")
    }

}
