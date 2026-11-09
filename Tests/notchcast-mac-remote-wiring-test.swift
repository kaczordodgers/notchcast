// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/SendFiles/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/UpdateRemote/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/MachRemoteShell.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/SendFilesModule.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/UpdateRemoteModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

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
        let suite = "remote-wiring-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.remoteMacAddress = "fake-mac"
        preferences.remoteUpdatePath = "/tools/update.sh"
        for feature: NotchcastFeature in [.machRemote, .sendFiles, .updateRemote, .backupStatus, .linkHealth] {
            precondition(!preferences.isOn(feature))
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
    }
}
