// notchcast-sources: Tinycast/Features/BackupStatus/Model/*.swift
// notchcast-sources: Tinycast/Features/BackupStatus/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastCore+RemoteNotice.swift
// notchcast-sources: Tinycast/Features/BackupStatus/BackupStatusModule+Live.swift
import Foundation

@MainActor enum NotchcastCore {}
@MainActor enum IslandHUDRouter {
    @discardableResult static func post(_ text: String) -> UUID? { nil }
}

@main
enum BackupStatusTest {
    @MainActor static func main() async throws {
        func check(_ condition: Bool) { precondition(condition) }
        let noticeSuite = "backup-notice-test." + UUID().uuidString
        defer { UserDefaults(suiteName: noticeSuite)?.removePersistentDomain(forName: noticeSuite) }
        let noticePreferences = NotchcastPreferences(suiteName: noticeSuite)
        var configurationNotices: [String] = []
        let unconfigured = BackupStatusModule(path: { "" }, post: { text in
            NotchcastCore.deliverRemoteNotice(text, preferences: noticePreferences) { configurationNotices.append($0) }
        })
        noticePreferences.set(.islandStatusMessages, false)
        unconfigured.start()
        check(configurationNotices.isEmpty)
        noticePreferences.set(.islandStatusMessages, true)
        unconfigured.start()
        check(configurationNotices == [String(localized: "Backup status path is not configured.")])
        var typedPath = ""
        var watchedCount = 0
        var restarts: [@MainActor () -> Void] = []
        let lateConfigured = BackupStatusModule(read: { Data() }, watch: { _ in
            watchedCount += 1
            return {}
        }, schedule: { _, action in
            restarts.append(action)
            return {}
        }, configurationNotice: { typedPath.isEmpty ? "unset" : nil }, post: { _ in })
        lateConfigured.pathChanged()
        check(restarts.isEmpty)
        lateConfigured.start()
        check(watchedCount == 0)
        typedPath = "/tmp/status.json"
        lateConfigured.pathChanged()
        restarts.removeLast()()
        check(watchedCount == 1)
        lateConfigured.pathChanged()
        restarts.removeLast()()
        check(watchedCount == 2)
        lateConfigured.stop()
        restarts.removeAll()
        lateConfigured.pathChanged()
        check(restarts.isEmpty)
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
        var data = try fixture()
        var clock = now
        var changed: (@MainActor () -> Void)?
        var deadline: (@MainActor () -> Void)?
        var notices: [String] = []
        var stopped = false
        let module = BackupStatusModule(read: { data }, watch: { action in
            changed = action
            return { stopped = true }
        }, schedule: { _, action in
            deadline = action
            return { deadline = nil }
        }, now: { clock }, post: { notices.append($0) })
        let suite = "backup-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        check(!preferences.isOn(.backupStatus))
        let controller = NotchcastModuleController([
            .init(requires: [.backupStatus], module: module),
        ], preferences: preferences)
        preferences.set(.backupStatus, true)
        controller.run()
        for _ in 0..<100 { await Task.yield() }
        check(notices.isEmpty && deadline != nil)
        clock = now.addingTimeInterval(7200)
        deadline?()
        check(notices.count == 1)
        deadline?()
        check(notices.count == 1)
        clock = now
        data = try fixture("failed")
        changed?()
        for _ in 0..<100 { await Task.yield() }
        check(notices.count == 2)
        changed?()
        for _ in 0..<100 { await Task.yield() }
        check(notices.count == 2)
        preferences.set(.backupStatus, false)
        for _ in 0..<100 { await Task.yield() }
        check(stopped && deadline == nil)
        changed?()
        for _ in 0..<100 { await Task.yield() }
        check(notices.count == 2)
        print("Backup status: parser, monitoring, deadlines and switch lifecycle passed")
    }
}
