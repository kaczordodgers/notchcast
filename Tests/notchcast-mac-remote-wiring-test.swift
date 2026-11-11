// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/SendFiles/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/UpdateRemote/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/MachRemoteShell.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/SendFilesModule.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/UpdateRemoteModule.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/MachRemote/MachRemoteModule.swift
// notchcast-sources: Tinycast/Features/MachRemote/MachRemoteModule+Registration.swift
// notchcast-sources: Tinycast/Features/MachRemote/Service/MachSSHProcessRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-kit: host
import Foundation

enum DialogTone { case danger }
@MainActor final class AppCore {}

@MainActor
final class RemoteCalls {
    var calls: [[String]] = []
    var blocking = false
    var cancelled = 0
    func record(_ executable: String, _ arguments: [String]) async throws -> MachSSH.Result {
        precondition(executable == "/usr/bin/ssh")
        calls.append(arguments)
        if blocking, arguments.last?.hasPrefix("rm -rf") != true {
            do { try await Task.sleep(for: .seconds(30)) } catch {
                cancelled += 1
                throw error
            }
        }
        return MachSSH.Result(status: 0, output: "")
    }
}

@main @MainActor
struct MacRemoteWiringTest {
    static func main() async throws {
        let calls = RemoteCalls()
        let runner: MachSSH.Runner = { executable, arguments in try await calls.record(executable, arguments) }
        let shell = MachRemoteShell(ssh: MachSSH(address: "fake-mac", runner: runner))
        _ = try await MachSendFilesRunner(shell: shell).run("/usr/bin/ssh", arguments: ["fake-mac", "uptime"]) { _ in }
        _ = try await MachUpdateRunner(shell: shell).run("/usr/bin/ssh", arguments: ["fake-mac", "uptime"]) { _ in }
        precondition(calls.calls == Array(repeating: MachSSH.options + ["fake-mac", "uptime"], count: 2))
        let own = ["-T", "-o", "ConnectTimeout=10"]
        _ = try await shell.run("/usr/bin/ssh", arguments: own + ["--", "fake-mac", "uptime"])
        precondition(calls.calls.removeLast() == own + MachSSH.options + ["fake-mac", "uptime"], "caller ssh options come first")
        var copies: [[String]] = []
        let copier = MachRemoteShell(ssh: MachSSH(address: "fake-mac") { executable, arguments in
            precondition(executable == "/usr/bin/rsync")
            await MainActor.run { copies.append(arguments) }
            return MachSSH.Result(status: 0, output: "")
        })
        _ = try await copier.run("/usr/bin/rsync", arguments: ["-a", "-e", "ssh -o StrictHostKeyChecking=yes", "from", "to"])
        let remoteShell = "'/usr/bin/ssh' -o StrictHostKeyChecking=yes " + MachSSH.options.map(MachSSH.quote).joined(separator: " ")
        precondition(copies == [["-a", "-e", remoteShell, "from", "to"]], "caller rsync shell options are kept")
        let suite = "remote-wiring-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.remoteMacAddress = "fake-mac"
        preferences.remoteUpdatePath = "/tools/update.sh"
        for feature: NotchcastFeature in [.machRemote, .sendFiles, .updateRemote, .backupStatus, .linkHealth] {
            precondition(!preferences.isOn(feature) && !feature.needsIsland && !feature.isSystemFeature)
            precondition(feature.settingsGroup == .system)
        }
        let send = SendFilesModule(preferences: preferences, runner: runner, post: { _ in })
        let update = UpdateRemoteModule(preferences: preferences, runner: runner, post: { _ in })
        let controller = NotchcastModuleController([
            .init(requires: [.machRemote, .sendFiles], module: send),
            .init(requires: [.machRemote, .updateRemote], module: update)
        ], preferences: preferences)
        controller.run()
        preferences.set(.sendFiles, true)
        preferences.set(.updateRemote, true)
        for _ in 0..<100 { await Task.yield() }
        precondition(!send.isRunning && !update.isRunning)
        send.send([URL(fileURLWithPath: "/synthetic-file")])
        update.update()
        precondition(calls.calls.count == 2)
        preferences.set(.machRemote, true)
        for _ in 0..<100 { await Task.yield() }
        precondition(send.isRunning && update.isRunning)
        calls.blocking = true
        send.send([URL(fileURLWithPath: "/synthetic-file")])
        update.update()
        for _ in 0..<100 { await Task.yield() }
        precondition(calls.calls.count == 4)
        preferences.set(.machRemote, false)
        for _ in 0..<100 { await Task.yield() }
        await send.coordinator?.waitForCompletion()
        precondition(!send.isRunning && !update.isRunning)
        precondition(calls.cancelled == 2)
        let count = calls.calls.count
        send.send([URL(fileURLWithPath: "/synthetic-file")])
        update.update()
        precondition(calls.calls.count == count)
        let entries = MachRemoteModule.register(AppCore())
        precondition(entries.map(\.requires) == [[.machRemote], [.machRemote, .sendFiles], [.machRemote, .updateRemote]])
        precondition(entries.allSatisfy(\.requiresAny.isEmpty) && entries[0].module === MachRemoteModule.shared)
        precondition(entries[1].module === SendFilesModule.shared && entries[2].module === UpdateRemoteModule.shared)
        var results: [String] = []
        NotchcastHost.current.remoteResult = { results.append($0) }
        SendFilesModule.shared.post("sent")
        UpdateRemoteModule.shared.post("updated")
        precondition(results == ["sent", "updated"])
    }
}
