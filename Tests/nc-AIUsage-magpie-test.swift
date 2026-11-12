// notchcast-sources: Tinycast/Features/AIUsage/Model/*.swift
// notchcast-reads: Tests/Fixtures/ai-usage/magpie-quotas.json
import Foundation

@main
struct MagpieQuotaTests {
    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first ?? "Tests/Fixtures/ai-usage/magpie-quotas.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let now = try Date("2026-11-11T22:30:00Z", strategy: .iso8601)
        let snapshots = try MagpieQuotaDecoder.decode(data, now: now)
        precondition(snapshots.count == 8)
        precondition(Set(snapshots.map(\.accountID)).count == 8)
        precondition(snapshots[0].accountName == "Claude Ultra")
        precondition(snapshots[6].accountName == "Grok" && snapshots[7].accountName == "Codex")
        precondition(snapshots[0].windows[0].resetsAt == nil)
        precondition(snapshots[7].windows[1].resetsAt == nil)
        let offset = try Date("2026-11-16T02:00:00Z", strategy: .iso8601)
        precondition(snapshots[0].windows[1].resetsAt == offset)
        let fractional = try Date("2026-11-13T12:49:06Z", strategy: .iso8601).addingTimeInterval(0.377)
        precondition(abs(snapshots[6].windows[0].resetsAt!.timeIntervalSince(fractional)) < 0.001)
        precondition(snapshots[2].status == .stale && snapshots[2].asOf != nil)
        precondition(snapshots[0].status == .available)
        let aged = try MagpieQuotaDecoder.decode(data, now: now.addingTimeInterval(16 * 60))
        precondition(aged.allSatisfy { $0.status == .stale })
        precondition(snapshots[0].windows.map(\.percentLeft) == [100, 46, 87])
        precondition(snapshots[1].windows.map(\.percentLeft) == [100, 32, 0])
        precondition(snapshots[6].windows[0].percentLeft == 7)
        precondition(snapshots[7].windows.map(\.percentLeft) == [98, 100])
        var payload = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var accounts = payload["data"] as! [[String: Any]]
        accounts[0]["user"] = ["unexpected": [1, 2, 3]]
        payload["data"] = accounts
        let ignoredUser = try MagpieQuotaDecoder.decode(JSONSerialization.data(withJSONObject: payload), now: now)
        precondition(ignoredUser == snapshots, "User is not decoded")
        var windows = accounts[0]["windows"] as! [[String: Any]]
        windows[0]["remaining"] = -999
        accounts[0]["windows"] = windows
        payload["data"] = accounts
        let ignoredRemaining = try MagpieQuotaDecoder.decode(JSONSerialization.data(withJSONObject: payload), now: now)
        precondition(ignoredRemaining == snapshots, "Percent left is calculated from used")
        windows[0]["used"] = 101
        accounts[0]["windows"] = windows
        payload["data"] = accounts
        do {
            _ = try MagpieQuotaDecoder.decode(JSONSerialization.data(withJSONObject: payload), now: now)
            preconditionFailure("Invalid percentage must fail at the boundary")
        } catch {}
        for snapshot in snapshots {
            let left = snapshot.windows.map { "\($0.label)=\($0.percentLeft)% left" }.joined(separator: ", ")
            print("\(snapshot.accountName): \(left)")
        }
        print("PASS: 8 accounts, offset and fractional dates, null fields, stale status, percent left, user omitted")
    }
}
