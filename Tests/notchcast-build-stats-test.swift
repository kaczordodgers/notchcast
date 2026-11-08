// notchcast-reads: Tests/fixtures/build-stats-v1.json
// notchcast-sources: Tinycast/Features/BuildStats/Model/*.swift
import Foundation

@main
struct BuildStatsTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Tests/fixtures/build-stats-v1.json"))
        let snapshot = try BuildStatsSnapshot.decode(data)
        try snapshot.validate()
        precondition(snapshot.tokens.first?.model == "model-a")
        let roundTrip = try BuildStatsSnapshot.decode(JSONEncoder().encode(snapshot))
        precondition(roundTrip == snapshot)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Fixture must be an object")
        }
        func reject(_ key: String, _ value: Any, _ expected: BuildStatsSnapshot.ValidationError) throws {
            var changed = object
            changed[key] = value
            do {
                _ = try BuildStatsSnapshot.decode(JSONSerialization.data(withJSONObject: changed))
                fatalError("Accepted invalid \(key)")
            } catch let error as BuildStatsSnapshot.ValidationError {
                precondition(error == expected, "Unexpected \(error)")
            }
        }
        try reject("schemaVersion", 2, .unsupportedVersion(2))
        try reject("tokens", [["model": "model-a", "effort": "high", "inputTokens": -1,
                               "outputTokens": 0]], .invalidValue("tokens"))
        try reject("timeline", [["date": "2026-02-30", "summary": "Example"]], .invalidDate("timeline"))
        try reject("changelog", [["date": "2026-01-02", "summary": "Example"],
                                 ["date": "2026-01-01", "summary": "Example"]], .datesOutOfOrder("changelog"))
        try reject("qualityMetrics", ["checks": -1], .invalidValue("metric value"))
        try reject("qualityMetrics", [String(repeating: "a", count: 81): 0], .limitExceeded("metric name"))
        try reject("timeline", [["date": "2026-01-01", "summary": " "]], .invalidValue("summary"))
        try reject("timeline", Array(repeating: ["date": "2026-01-01", "summary": "Example"], count: 1001),
                   .limitExceeded("timeline"))
        try reject("qualityMetrics", Dictionary(uniqueKeysWithValues: (0...100).map { ("metric-\($0)", 0) }),
                   .limitExceeded("qualityMetrics"))
        do {
            _ = try BuildStatsSnapshot.decode(Data(repeating: 32, count: BuildStatsSnapshot.maximumBytes + 1))
            fatalError("Accepted oversized input")
        } catch let error as BuildStatsSnapshot.ValidationError {
            precondition(error == .limitExceeded("bytes"))
        }
        print("Build stats: decode, round trip, validation and rejection passed")
    }
}
