// notchcast-sources: Tinycast/Features/SystemTools/Model/*.swift Tinycast/Features/SystemTools/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemTools/UI/SystemToolsProcessRunner.swift Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/*.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/*.swift
import Foundation

@main
struct SystemToolsTests {
    static func main() throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        func refuses(_ body: () throws -> Void) {
            do { try body(); preconditionFailure("Expected refusal") } catch { checks += 1 }
        }
        let home = "/tmp/system-tools-fixture"
        let path = home + "/Library/LaunchAgents/org.example.job.plist"
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "Label": "org.example.job", "ProgramArguments": ["/opt/example tool", "--start"]
        ], format: .xml, options: 0)
        let item = try StartupItem.decode(data, path: path, kind: .userAgent, disabled: false, loaded: true)
        expect(item.program == "/opt/example tool", "plist arguments")
        var commands: [[String]] = []
        try StartupItemService().apply(item, enabled: false, uid: 501, home: home) { commands.append($0) }
        expect(commands == [["disable", "gui/501/org.example.job"],
                            ["bootout", "gui/501/org.example.job"]], "disable before unload")
        let off = try StartupItem.decode(data, path: path, kind: .userAgent, disabled: true, loaded: false)
        expect(try off.commands(enabled: true, uid: 501, home: home)
               == [["enable", "gui/501/org.example.job"], ["bootstrap", "gui/501", path]], "enable plan")
        let daemon = try StartupItem.decode(data, path: path, kind: .daemon, disabled: false, loaded: true)
        refuses { _ = try daemon.commands(enabled: false, uid: 501, home: home) }
        refuses { _ = try StartupItem.decode(Data(), path: path, kind: .userAgent) }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try data.write(to: folder.appending(path: "job.plist"))
        expect(try StartupItemService().read(folder: folder, kind: .userAgent).count == 1, "scanner")
        try Data().write(to: folder.appending(path: "broken.plist"))
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "link.plist"),
                                                  withDestinationURL: folder.appending(path: "job.plist"))
        expect(try StartupItemService().read(folder: folder, kind: .userAgent).count == 1,
               "bad and symlinked plists skipped")
        let system = try StartupItem.decode(data, path: path, kind: .systemAgent)
        expect(try StartupItemService().status(system, uid: 501, disabledText: "") { _, _ in
            preconditionFailure("System items must not probe launchctl")
        } == system, "system plist only")
        enum ProbeFailure: Error { case failed }
        let unknown = try StartupItemService().status(item, uid: 501, disabledText: "") { _, _ in
            throw ProbeFailure.failed
        }
        expect(unknown.loaded == nil, "failed probe is unknown")
        let unloaded = try StartupItemService().status(item, uid: 501, disabledText: "") { _, _ in
            throw SystemToolsProcessRunner.Failure.failed(113)
        }
        expect(unloaded.loaded == false, "113 means unloaded")
        expect(try unloaded.commands(enabled: true, uid: 501, home: home).count == 2,
               "unloaded agents can bootstrap")
        expect(try StartupItemService().status(item, uid: 501, disabledText: "") { _, _ in "" }.loaded == true,
               "next probe still succeeds")

        let sudo = "# sudo\nauth include sudo_local\nauth required pam_opendirectory.so\n"
        let local = "# custom\nauth optional pam_other.so\n"
        let enabled = try TouchIDPolicy.replacement(sudo: sudo, local: local, enabled: true)
        expect(enabled.map { TouchIDPolicy.enabled(in: $0) } == true, "enabled")
        expect(try TouchIDPolicy.replacement(sudo: sudo, local: enabled, enabled: true) == nil, "idempotent")
        expect(try TouchIDPolicy.replacement(sudo: sudo, local: enabled, enabled: false) == local, "preserves rules")
        expect(!TouchIDPolicy.enabled(in: "# auth sufficient pam_tid.so"), "comment ignored")
        refuses { _ = try TouchIDPolicy.replacement(sudo: "", local: nil, enabled: true) }
        refuses { _ = try TouchIDPolicy.replacement(sudo: sudo, local: "auth required pam_tid.so", enabled: false) }
        try sudo.write(to: folder.appending(path: "sudo"), atomically: true, encoding: .utf8)
        expect(try TouchIDService().read(directory: folder).local == nil, "absent sudo_local")
        var rootVerb: TouchIDRootVerbs?
        try TouchIDService().apply(.enableSudoTouchID) { rootVerb = $0 }
        expect(rootVerb == .enableSudoTouchID, "injected root verb")

        let policy = NotificationCleanupPolicy(diskEjectionTitles: ["Disk Not Ejected Properly"])
        let alert = NotificationCleanupPolicy.Alert(identifier: "one", title: "Disk Not Ejected Properly",
                                                     isIndividualAlert: true, actions: ["Clear All", "AXClose"])
        expect(policy.closeAction(for: alert) == "AXClose", "individual close only")
        let stack = NotificationCleanupPolicy.Alert(identifier: "stack", title: alert.title,
                                                     isIndividualAlert: false, actions: ["Clear All"])
        expect(policy.closeAction(for: stack) == nil, "stack refused")
        var closed = 0
        let cleanup = NotificationCleanupService(policy: policy)
        expect(try cleanup.apply(alerts: [alert, stack], trusted: true, current: { _ in alert },
                                 perform: { _, _ in closed += 1 }) == 1 && closed == 1, "injected close")
        expect(try cleanup.apply(alerts: [alert], trusted: false, current: { _ in alert },
                                 perform: { _, _ in preconditionFailure() }) == 0, "permission gate")

        let process = KillProcessEntry(pid: 42, parentPID: 1, uid: 501, startSeconds: 10,
                                       startMicroseconds: 123, path: "/Applications/Example.app/Contents/MacOS/Example")
        let reused = KillProcessEntry(pid: 42, parentPID: 1, uid: 501, startSeconds: 10,
                                      startMicroseconds: 124, path: process.path)
        let child = KillProcessEntry(pid: 43, parentPID: 42, uid: 501, startSeconds: 11,
                                     startMicroseconds: 0, path: process.path)
        expect(process.tree(in: [process, child]).map(\.pid) == [43, 42], "children first")
        expect(!process.sameIdentity(as: reused), "microsecond reuse")
        expect(!process.canStop(uid: 502, ownPID: 99), "other owner")
        expect(!process.canStop(uid: 501, ownPID: 42), "self protected")
        let service = KillProcessService()
        var signals = 0
        refuses {
            try service.apply(targets: [process], signal: .terminate, uid: 501, ownPID: 99,
                              lookup: { _ in reused }, run: { _, _ in signals += 1 })
        }
        expect(signals == 0, "no stale signal")
        try service.apply(targets: [process], signal: .terminate, uid: 501, ownPID: 99,
                          lookup: { _ in process }, run: { _, signal in
                              expect(signal == .terminate, "TERM plan")
                              signals += 1
                          })
        expect(signals == 1, "injected signal only")
        expect(service.read(pid: -1) == nil, "invalid pid")
        expect(service.read().allSatisfy { $0.pid > 0 }, "read process inventory")
        expect(service.read(pid: ProcessInfo.processInfo.processIdentifier)?.pid
               == ProcessInfo.processInfo.processIdentifier, "read own identity only")
        print("\(checks) passed, 0 failed")
    }
}
