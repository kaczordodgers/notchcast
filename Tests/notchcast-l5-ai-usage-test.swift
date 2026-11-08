// notchcast-reads: Tests/Fixtures/ai-usage/cache-shapes.json
// notchcast-sources: Tinycast/Features/AIUsage/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/Service/*.swift
import Foundation

@main
struct AIUsageTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: "Tests/Fixtures/ai-usage/cache-shapes.json")
        let samples = try JSONDecoder().decode([String: Sample].self, from: Data(contentsOf: fixture))
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        for (name, sample) in samples {
            let data = try JSONEncoder().encode(sample)
            try data.write(to: directory.appendingPathComponent(name + ".json"))
            let parsed = try AIUsageParser.parse(data, providerID: name, now: now, staleAfter: 900)
            assert(parsed.providerID == name)
            assert(parsed.windows.count == sample.usageLimits?.windows.count ?? 0)
            assert(parsed.status == (parsed.windows.isEmpty ? .noData : .stale))
        }
        let provider = AIUsageProvider(cacheDirectory: directory, clock: { now })
        let results = await provider.refresh()
        assert(results.count == samples.count)
        let file = directory.appendingPathComponent("test.json")
        let valid = Data("""
        {"displayName":"Plan","usageLimits":{"checkedAt":"2026-11-04T00:00:00Z",
        "windows":[{"id":"weekly","label":"Weekly","usedPercent":42,
        "resetsAt":"2026-11-04T01:00:00.000Z"}]}}
        """.utf8)
        let instant = ISO8601DateFormatter().date(from: "2026-11-04T00:00:00Z")!
        let parsed = try AIUsageParser.parse(valid, providerID: "test", now: instant, staleAfter: 900)
        assert(parsed.status == .available)
        assert(parsed.windows[0].used == 42 && parsed.windows[0].limit == 100)
        assert(parsed.windows[0].secondsUntilReset(at: instant) == 3600)
        assert(parsed.windows[0].secondsUntilReset(at: instant.addingTimeInterval(7200)) == 0)
        let stale = try AIUsageParser.parse(valid, providerID: "test",
                                          now: instant.addingTimeInterval(900), staleAfter: 900)
        assert(stale.status == .stale)
        let expired = try AIUsageParser.parse(valid, providerID: "test",
                                            now: instant.addingTimeInterval(3600), staleAfter: 7200)
        assert(expired.status == .stale)
        let validText = String(bytes: valid, encoding: .utf8)!
        for invalid in [
            validText.replacingOccurrences(of: "42", with: "-1"),
            validText.replacingOccurrences(of: "2026-11-04T01:00:00.000Z", with: "bad")
        ] {
            do {
                _ = try AIUsageParser.parse(Data(invalid.utf8), providerID: "test",
                                           now: instant, staleAfter: 900)
                fatalError("Accepted invalid window")
            } catch {}
        }
        try valid.write(to: file)
        let fresh = AIUsageProvider(cacheDirectory: directory, clock: { instant })
        let firstRead = await fresh.refresh()
        assert(firstRead.first { $0.providerID == "test" }?.status == .available)
        try Data("broken".utf8).write(to: file)
        let secondRead = await fresh.refresh()
        assert(secondRead.first { $0.providerID == "test" }?.status == .unreadable)
        try FileManager.default.removeItem(at: directory)
        let missing = await provider.refresh()
        assert(missing.first?.status == .noData)
        print("AI usage: all cache shapes, lazy refresh, missing, malformed, stale and reset math passed")
    }

    struct Sample: Codable {
        let displayName: String
        let usageLimits: Limits?
    }

    struct Limits: Codable {
        let checkedAt: String
        let windows: [Window]
        let unavailable: [String: String]?
        let resetCredits: Credits?
    }

    struct Credits: Codable {
        let availableCount: Int
        let nextExpiresAt: String?
    }

    struct Window: Codable {
        let id: String
        let label: String
        let usedPercent: Double
        let resetsAt: String?
        let windowDurationMins: Double?
    }
}
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Model/OtherMacUsageSnapshot.swift
