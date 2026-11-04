// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/UpdateRemote/*.swift
import Foundation

@MainActor
private final class FakeRunner: UpdateRemoteShellRunning {
    var sshAlias = "fixture-mac"
    var status: Int32 = 0
    var lines = [String]()
    var calls = [[String]]()
    var waits = false

    func run(_ executable: String, arguments: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> UpdateRemoteProcessResult {
        precondition(executable == "/usr/bin/ssh")
        calls.append(arguments)
        for line in lines { output(line) }
        if waits { try await Task.sleep(for: .seconds(60)) }
        return UpdateRemoteProcessResult(status: status, output: lines.joined(separator: "\n"))
    }
}

@main
struct UpdateRemoteTest {
    @MainActor static func main() async {
        let expected = ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "--", "fixture-mac",
                        "exec '/tools/update.sh'"]
        precondition(UpdateRemoteCoordinator.arguments(alias: "fixture-mac", scriptPath: "/tools/update.sh") == expected)
        for alias in ["", "-oProxyCommand=x", "host;touch x", "host\nfoo", "$(id)"] {
            precondition(UpdateRemoteCoordinator.arguments(alias: alias) == nil)
        }
        var progress = UpdateRemoteProgress()
        let unconfiguredRunner = FakeRunner()
        var configurationNotices: [String] = []
        let unconfigured = UpdateRemoteCoordinator(runner: unconfiguredRunner,
            post: { configurationNotices.append($0) })
        unconfigured.start()
        precondition(unconfiguredRunner.calls.isEmpty)
        precondition(configurationNotices == [String(localized: "Remote Mac path is not configured.")])
        unconfiguredRunner.sshAlias = ""
        unconfigured.start()
        precondition(unconfiguredRunner.calls.isEmpty)
        precondition(configurationNotices.last == String(localized: "Set the remote Mac address in Settings"))
        precondition(UpdateRemoteCoordinator.arguments(alias: "user@2001:db8::1", scriptPath: "/tools/update.sh") != nil)
        progress.consume("── brew update")
        precondition(progress.step == "brew update")
        progress.consume("── npm globals (latest)")
        progress.consume("✗ needs attention: brew-update npm-globals")
        precondition(progress.result(status: 1) == .failed(step: "brew-update npm-globals"))
        precondition(progress.result(status: 255) == .unreachable)
        var empty = UpdateRemoteProgress()
        empty.consume("Nothing to do.")
        precondition(empty.result(status: 0) == .nothingToDo)
        precondition(UpdateRemoteProgress().result(status: 0) == .updated)
        for status: Int32 in [0, 1, 255] {
            let runner = FakeRunner()
            runner.status = status
            runner.lines = ["── brew upgrade", "synthetic progress"]
            var notices = [String]()
            let coordinator = UpdateRemoteCoordinator(runner: runner, scriptPath: "/tools/update.sh",
                post: { notices.append($0) })
            coordinator.start()
            coordinator.start()
            while coordinator.isRunning { await Task.yield() }
            precondition(runner.calls == [expected])
            precondition(notices.first == "── brew upgrade")
            let result: UpdateRemoteProgress.Result = status == 0 ? .updated :
                status == 255 ? .unreachable : .failed(step: "brew upgrade")
            precondition(coordinator.result == result)
        }
        let runner = FakeRunner()
        runner.waits = true
        let coordinator = UpdateRemoteCoordinator(runner: runner, scriptPath: "/tools/update.sh", post: { _ in })
        coordinator.start()
        while runner.calls.isEmpty { await Task.yield() }
        coordinator.cancel()
        await Task.yield()
        precondition(coordinator.result == .cancelled && !coordinator.isRunning)
        print("remote update fixtures passed")
    }
}
