// notchcast-sources: Tinycast/Features/AIUsage/Model/*.swift
// notchcast-reads: Tests/Fixtures/ai-usage/magpie-quotas.json
import Foundation

@main
struct MagpieQuotaTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/ai-usage/magpie-quotas.json"))
        let now = try Date("2026-11-11T22:30:00Z", strategy: .iso8601)
        let snapshots = try MagpieQuotaDecoder.decode(data, now: now)
        precondition(snapshots.count == 8)
        precondition(Set(snapshots.map(\.accountID)).count == 8)
        precondition(snapshots.map(\.accountName) == (65...72).map { "Account " + String(UnicodeScalar($0)!) })
        precondition(snapshots[0].windows[0].resetsAt == nil)
        precondition(snapshots[7].windows[1].resetsAt == nil)
        precondition(snapshots[3].windows.count == 4)
        let offset = try Date("2026-11-16T12:00:00Z", strategy: .iso8601)
        precondition(snapshots[0].windows[1].resetsAt == offset)
        let fractional = try Date("2026-11-13T12:00:00Z", strategy: .iso8601)
        precondition(snapshots[6].windows[0].resetsAt == fractional)
        precondition(snapshots[2].status == .stale && snapshots[2].asOf != nil)
        precondition(snapshots[0].status == .available)
        let aged = try MagpieQuotaDecoder.decode(data, now: now.addingTimeInterval(16 * 60))
        precondition(aged.allSatisfy { $0.status == .stale })
        precondition(snapshots[0].windows.map(\.percentLeft) == [75, 60, 10])
        precondition(snapshots[1].windows.map(\.percentLeft) == [0, 85, 95])
        precondition(snapshots[6].windows[0].percentLeft == 25)
        precondition(snapshots[7].windows.map(\.percentLeft) == [50, 80])

        var payload = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var accounts = payload["data"] as! [[String: Any]]
        accounts[0]["user"] = ["unexpected": [1, 2, 3]]
        payload["data"] = accounts
        let ignoredUser = try MagpieQuotaDecoder.decode(JSONSerialization.data(withJSONObject: payload), now: now)
        precondition(ignoredUser == snapshots, "Unknown identity field is not decoded")
        var windows = accounts[0]["windows"] as! [[String: Any]]
        windows[0]["remaining"] = -999
        accounts[0]["windows"] = windows
        payload["data"] = accounts
        let ignoredRemaining = try MagpieQuotaDecoder.decode(JSONSerialization.data(withJSONObject: payload), now: now)
        precondition(ignoredRemaining == snapshots, "Percent left is calculated from used")
        windows[0]["used"] = 100.5
        windows[1]["used"] = NSNull()
        windows.append(["name": "Invalid reset", "used": 20, "resetsAt": "invalid"])
        windows.append(["used": 50])
        accounts[0]["windows"] = windows
        payload["data"] = accounts
        let partial = try MagpieQuotaDecoder.decode(JSONSerialization.data(withJSONObject: payload), now: now)
        precondition(partial.count == 8 && Array(partial.dropFirst()) == Array(snapshots.dropFirst()))
        precondition(partial[0].windows.map(\.percentLeft) == [0, 10])
        precondition(partial[0].windows.map(\.id) == ["0", "2"])

        let reset = now.addingTimeInterval(30)
        let exhausted = AIUsageSnapshot.Window(id: "reset", label: "Session", used: 100, limit: 100,
                                             resetsAt: reset)
        precondition(exhausted.percentLeft(at: now, readAt: now) == 0)
        precondition(exhausted.percentLeft(at: reset, readAt: now) == 100)
        precondition(exhausted.percentLeft(at: reset.addingTimeInterval(1), readAt: now) == 100)
        precondition(exhausted.percentLeft(at: reset, readAt: reset) == 0)
        precondition(exhausted.percentLeft(at: reset.addingTimeInterval(2), readAt: reset.addingTimeInterval(1)) == 0)
        precondition(exhausted.secondsUntilReset(at: now) == 30)
        precondition(exhausted.secondsUntilReset(at: reset.addingTimeInterval(-0.1)) == 1)
        precondition(exhausted.secondsUntilReset(at: reset) == nil)
        precondition(exhausted.secondsUntilReset(at: reset.addingTimeInterval(1)) == nil)
        precondition(snapshots[0].windows[0].secondsUntilReset(at: now) == nil)
        print("PASS: synthetic accounts, both date formats, null and empty aliases, partial windows, clamp, reset rollover")
    }
}
