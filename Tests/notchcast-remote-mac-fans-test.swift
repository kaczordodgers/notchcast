// notchcast-sources: Tinycast/Features/MachRemote/Model/MachSSH.swift
// notchcast-sources: Tinycast/Features/MachRemote/RemoteMacFansModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/*.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl.swift
import Foundation

@MainActor
final class FansFakeTransport {
    var calls: [[String]] = []
    var status: Int32 = 0
    var output = "ok\n"
    var throwsError = false

    func run(_ executable: String, _ arguments: [String]) throws -> MachSSH.Result {
        precondition(executable == "/usr/bin/ssh")
        calls.append(arguments)
        if throwsError { throw MachSSH.RouteError.unavailable }
        return .init(status: status, output: output)
    }
}

@main @MainActor
struct RemoteMacFansTest {
    static func main() async {
        let suite = "remote-fans-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.remoteMacAddress = "fake-mac"
        precondition(!preferences.isOn(.remoteMacFans) && !NotchcastFeature.remoteMacFans.needsIsland)
        let fake = FansFakeTransport()
        var notices: [String] = []
        let module = RemoteMacFansModule(preferences: preferences,
            runner: { try await fake.run($0, $1) }, post: { notices.append($0) })
        module.start()
        module.set(.max)
        await module.waitUntilIdle()
        preferences.set(.remoteMacFans, true)
        module.set(.max)
        await module.waitUntilIdle()
        precondition(fake.calls.isEmpty)
        preferences.set(.machRemote, true)
        for (mode, verb): (FanControl.Mode, String) in [(.auto, "fans-auto"), (.medium, "fans-medium"), (.max, "fans-max")] {
            module.set(mode)
            await module.waitUntilIdle()
            precondition(fake.calls.last == MachSSH.options + ["fake-mac",
                "exec /usr/bin/sudo -n '/Library/PrivilegedHelperTools/app.notchcast.root' '" + verb + "'"])
        }
        precondition(notices.isEmpty)
        fake.status = 255
        module.set(.auto)
        await module.waitUntilIdle()
        precondition(notices.count == 1)
        fake.status = 0
        fake.output = "unexpected"
        module.set(.medium)
        await module.waitUntilIdle()
        precondition(notices.count == 2)
        fake.throwsError = true
        module.set(.max)
        await module.waitUntilIdle()
        precondition(notices.count == 3 && notices.allSatisfy { $0 == notices[0] })
        let count = fake.calls.count
        module.stop()
        module.set(.auto)
        await module.waitUntilIdle()
        precondition(fake.calls.count == count)
        print("PASS: remote fan modes, gates and failure notices (fake transport)")
    }
}
