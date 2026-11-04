// notchcast-sources: Tinycast/Features/BackupStatus/Model/*.swift
import Foundation

@main
enum BackupStatusTest {
    static func main() throws {
        func check(_ condition: Bool) { precondition(condition) }
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        let stamp = ISO8601DateFormatter().string(from: now)
        func fixture(_ result: String = "ok", changes: [String: Any] = [:]) throws -> Data {
            var object: [String: Any] = [
                "version": 1, "result": result, "message": NSNull(),
                "lastSuccess": stamp, "lastAttempt": stamp, "snapshotCount": 8,
                "oldestSnapshot": stamp, "newestSnapshot": stamp,
                "sourceBytes": 1000, "addedBytes": 100, "repoBytes": 2000,
                "targetFreeBytes": 3000, "lowSpace": false, "retention": "Last 2, 7 Daily, 4 Weekly",
                "restoreTest": ["at": stamp, "result": "ok"],
                "mbpTimeMachine": ["latest": stamp, "checkedAt": stamp, "error": NSNull()],
            ]
            object.merge(changes) { _, new in new }
            return try JSONSerialization.data(withJSONObject: object)
        }
        func issues(_ data: Data, at date: Date? = nil) throws -> [BackupStatusEngine.Issue] {
            BackupStatusEngine.issues(try BackupStatusEngine.parse(data), now: date ?? now, staleAfter: 7200)
        }
        func rejected(_ data: Data) {
            do {
                _ = try BackupStatusEngine.parse(data)
                preconditionFailure("Invalid status accepted")
            } catch {}
        }
        let healthy = try BackupStatusEngine.parse(fixture())
        precondition(healthy.snapshotCount == 8 && healthy.sourceBytes == 1000)
        precondition(healthy.restoreTest?.result == .ok && healthy.mbpTimeMachine?.latest == now)
        check(try issues(fixture()).isEmpty)
        check(try issues(fixture("warning", changes: ["message": "Unreadable files: 8"])) == [.warning])
        check(try issues(fixture("failed")) == [.failed])
        check(try issues(fixture("skipped")) == [.skipped])
        check(try issues(fixture(changes: ["lowSpace": true])) == [.lowSpace])
        check(try issues(fixture(changes: ["restoreTest": ["at": stamp, "result": "failed"]])) == [.restoreFailed])
        let remoteFailure: [String: Any] = ["latest": NSNull(), "error": "Peer unreachable"]
        check(try issues(fixture(changes: ["mbpTimeMachine": remoteFailure])) == [.remoteUnavailable])
        check(try issues(fixture(), at: now.addingTimeInterval(7200)) == [.stale, .remoteStale])
        check(try issues(fixture(), at: now.addingTimeInterval(7199)).isEmpty)
        check(try issues(fixture(changes: ["lastSuccess": NSNull()])) == [.stale])
        let noOptionalData = try fixture(changes: [
            "lastSuccess": NSNull(), "oldestSnapshot": NSNull(), "newestSnapshot": NSNull(),
            "sourceBytes": NSNull(), "addedBytes": NSNull(), "repoBytes": NSNull(),
            "targetFreeBytes": NSNull(), "retention": NSNull(), "restoreTest": NSNull(),
            "mbpTimeMachine": NSNull(),
        ])
        check(try issues(noOptionalData) == [.stale])
        precondition(BackupStatusEngine.issues(nil, now: now, staleAfter: 7200) == [.unavailable])
        rejected(try fixture(changes: ["version": 2]))
        rejected(try fixture(changes: ["snapshotCount": -1]))
        rejected(try fixture(changes: ["repoBytes": -1]))
        rejected(try fixture(changes: ["lastAttempt": "invalid"]))
        rejected(try fixture("unknown"))
        rejected(Data("{".utf8))
        print("Backup status: all synthetic parser and health fixtures passed")
    }
}
