// notchcast-sources: Tinycast/Features/AIUsage/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/Service/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Model/OtherMacUsageSnapshot.swift
import Foundation

@main
struct AIUsageCacheTest {
    static func main() throws {
        let home = URL(fileURLWithPath: "/synthetic/home", isDirectory: true)
        precondition(AIUsageProvider.cacheDirectory(path: "", homeDirectory: home).path
                     == "/synthetic/home/.t3/caches")
        precondition(AIUsageProvider.cacheDirectory(path: "/custom/cache", homeDirectory: home).path
                     == "/custom/cache")
        let otherHome = URL(fileURLWithPath: "/synthetic/other", isDirectory: true)
        precondition(AIUsageProvider.cacheDirectory(path: "", homeDirectory: otherHome).path
                     == "/synthetic/other/.t3/caches")
        for (field, expected) in [
            (",\"resetCredits\":{\"availableCount\":3}", 3),
            (",\"resetCredits\":{\"availableCount\":0}", 0),
            ("", nil),
            (",\"resetCredits\":null", nil),
            (",\"resetCredits\":false", nil),
            (",\"resetCredits\":{}", nil),
            (",\"resetCredits\":{\"availableCount\":\"odd\"}", nil),
            (",\"resetCredits\":{\"availableCount\":-1}", nil)
        ] as [(String, Int?)] {
            let data = Data("""
            {"displayName":"Synthetic account","usageLimits":{
            "checkedAt":"2026-11-04T00:00:00Z","windows":[]\(field)}}
            """.utf8)
            let snapshot = try AIUsageParser.parse(data, providerID: "codex-fixture",
                                                   now: Date(timeIntervalSince1970: 0), staleAfter: 900)
            precondition(snapshot.resetCredits?.availableCount == expected)
            precondition(snapshot.plan == "Synthetic account")
        }
        print("PASS: default and explicit paths, read-time home, reset credits and tolerant decoding")
    }
}
