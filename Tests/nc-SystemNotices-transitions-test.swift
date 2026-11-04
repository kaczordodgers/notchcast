import Foundation

@main
struct SystemNoticesTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { fatalError(message) }
        }
        var engine = SystemNoticeEngine()
        let manager = SystemNoticesManager(observeSystem: false)
        var notices: [SystemNoticeEngine.Notice] = []
        manager.onNotice = { notices.append($0) }
        manager.start()
        manager.consume(.wifi(true))
        manager.setSleeping(true)
        manager.consume(.wifi(false))
        manager.setLocked(true)
        manager.setSleeping(false)
        manager.consume(.wifi(false))
        manager.setLocked(false)
        manager.consume(.wifi(true))
        check(notices.isEmpty, "Sleep and lock route flaps stay quiet through wake and unlock")
        manager.consume(.wifi(false))
        check(notices == [.wifi(available: false)], "Monitoring resumes after the silent baseline")
        manager.stop()
        check(engine.consume(.wifi(true)).isEmpty, "Initial route is quiet")
        check(engine.consume(.wifi(true)).isEmpty, "Repeated route is quiet")
        check(engine.consume(.wifi(false)) == [.wifi(available: false)], "Route down is an edge")
        check(engine.consume(.wifi(true)) == [.wifi(available: true)], "Route up is an edge")
        check(engine.consume(.wifi(nil)).isEmpty, "Indeterminate path is quiet")
        check(engine.consume(.wifi(false)).isEmpty, "Path after unknown is a new baseline")
        check(engine.consume(.tailscale(.connected)).isEmpty, "Initial VPN is quiet")
        check(engine.consume(.tailscale(.needsLogin)) == [.tailscale(.needsLogin)], "Login transition")
        check(engine.consume(.tailscale(.needsApproval)) == [.tailscale(.needsApproval)], "Approval transition")
        check(engine.consume(.tailscale(.disconnected)) == [.tailscale(.disconnected)], "Disconnected transition")
        check(engine.consume(.tailscale(.unavailable)).isEmpty, "Missing CLI is quiet")
        check(engine.consume(.tailscale(.connected)).isEmpty, "CLI recovery establishes baseline")
        let states: [(String, TailscaleState)] = [
            ("Running", .connected), ("Stopped", .disconnected), ("Starting", .starting),
            ("NeedsLogin", .needsLogin), ("NeedsMachineAuth", .needsApproval), ("FutureState", .unavailable),
        ]
        for (raw, expected) in states {
            check(TailscaleState.parse(Data("{\"BackendState\":\"\(raw)\"}".utf8)) == expected, "Backend state \(raw)")
        }
        check(TailscaleState.parse(Data("{}".utf8)) == .unavailable, "Missing state rejected")
        check(TailscaleState.parse(Data("broken".utf8)) == .unavailable, "Malformed JSON rejected")
        check(engine.consume(.battery(.init(percent: 30, onBattery: true))).isEmpty, "Initial battery is quiet")
        check(engine.consume(.battery(.init(percent: 20, onBattery: true))) == [.lowBattery(percent: 20, threshold: 20)],
              "20% battery boundary")
        check(engine.consume(.battery(.init(percent: 19, onBattery: true))).isEmpty, "Same low episode is quiet")
        _ = engine.consume(.battery(.init(percent: 24, onBattery: true)))
        check(engine.consume(.battery(.init(percent: 20, onBattery: true))).isEmpty, "24% does not re-arm 20%")
        _ = engine.consume(.battery(.init(percent: 25, onBattery: true)))
        check(engine.consume(.battery(.init(percent: 20, onBattery: true))) == [.lowBattery(percent: 20, threshold: 20)],
              "25% re-arms 20%")
        check(engine.consume(.battery(.init(percent: 10, onBattery: true))) == [.lowBattery(percent: 10, threshold: 10)],
              "10% battery boundary")
        _ = engine.consume(.battery(.init(percent: 14, onBattery: false)))
        check(engine.consume(.battery(.init(percent: 10, onBattery: true))).isEmpty, "Brief charging does not re-arm")
        _ = engine.consume(.battery(.init(percent: 15, onBattery: false)))
        check(engine.consume(.battery(.init(percent: 10, onBattery: true))) == [.lowBattery(percent: 10, threshold: 10)],
              "15% re-arms 10%")
        _ = engine.consume(.battery(.init(percent: 30, onBattery: false)))
        check(engine.consume(.battery(.init(percent: 5, onBattery: false))).isEmpty, "External power never warns")
        check(engine.consume(.battery(.init(percent: 5, onBattery: true))) == [.lowBattery(percent: 5, threshold: 10)],
              "Unplug low reports only the more urgent crossed threshold")
        check(engine.consume(.battery(.init(percent: 101, onBattery: true))).isEmpty, "Invalid battery ignored")
        check(engine.consume(.battery(.init(percent: 5, onBattery: true))).isEmpty, "Recovered reading is quiet")
        var lowStartup = SystemNoticeEngine()
        check(lowStartup.consume(.battery(.init(percent: 9, onBattery: true))).isEmpty, "Low startup is quiet")
        check(lowStartup.consume(.battery(.init(percent: 8, onBattery: true))).isEmpty, "Startup spell remains quiet")
        var chargingStartup = SystemNoticeEngine()
        check(chargingStartup.consume(.battery(.init(percent: 9, onBattery: false))).isEmpty, "Charging startup is quiet")
        check(chargingStartup.consume(.battery(.init(percent: 9, onBattery: true)))
              == [.lowBattery(percent: 9, threshold: 10)], "Unplugging a low startup battery warns")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nc-notices-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func fixture(_ name: String, body: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }
        let valid = try fixture("valid", body: "printf '{\"BackendState\":\"Running\"}'\n")
        check(await TailscaleStatusService(executable: valid).read() == .connected, "CLI fixture decodes")
        let failure = try fixture("failure", body: "printf '{\"BackendState\":\"Running\"}'\nexit 1\n")
        check(await TailscaleStatusService(executable: failure).read() == .unavailable, "Nonzero exit rejected")
        let large = try fixture("large", body: "exec /usr/bin/yes x\n")
        check(await TailscaleStatusService(executable: large).read() == .unavailable, "Oversized output capped")
        let hanging = try fixture("hanging", body: "exec /bin/sleep 30\n")
        check(await TailscaleStatusService(executable: hanging, timeout: .milliseconds(50)).read() == .unavailable,
              "Deadline kills and reaps child")
        let task = Task { await TailscaleStatusService(executable: hanging).read() }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        check(await task.value == .unavailable, "Cancellation kills and reaps child")
        check(await TailscaleStatusService(executable: root.appendingPathComponent("absent")).read() == .unavailable,
              "Missing executable stays quiet")
        check(SystemNoticesManager.tailscaleInterval == .seconds(300), "Five-minute safety cadence")
        print("PASS: \(checks) notice edges, re-arming and bounded CLI checks")
    }
}
