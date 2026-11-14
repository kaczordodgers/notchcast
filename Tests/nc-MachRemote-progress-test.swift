// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift Tinycast/Features/MachRemote/Service/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/SendFiles/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/UpdateRemote/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/MachRemoteShell.swift
// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessOutputStream.swift
// notchcast-kit: platform
import Foundation

@main
@MainActor
struct MachRemoteProgressTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static let folder = FileManager.default.temporaryDirectory
        .appending(path: "nc-mach-progress-\(UUID().uuidString)")

    // Stands in for rsync and the remote script: a real child that blocks on a gate file.
    static func script(_ before: String, _ after: String, gate: URL, pid: URL) -> String {
        "echo $$ > '\(pid.path)'; printf '\(before)'; " +
            "while [ ! -e '\(gate.path)' ] && kill -0 $PPID; do sleep 0.05; done; printf '\(after)'"
    }

    static func runner(rsync: String, ssh: String) -> MachSSH.Runner {
        { executable, _, onLine in
            switch executable {
            case "/usr/bin/rsync": try await MachSSHProcessRunner.run("/bin/sh", ["-c", rsync], onLine: onLine)
            case "/usr/bin/ssh" where !ssh.isEmpty:
                try await MachSSHProcessRunner.run("/bin/sh", ["-c", ssh], onLine: onLine)
            default: MachSSH.Result(status: 0, output: "")
            }
        }
    }

    static func waitUntil(_ message: String, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition() {
            check(ContinuousClock.now < deadline, "timed out: \(message)")
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    static func alive(_ pid: URL) -> Bool {
        guard let text = try? String(contentsOf: pid, encoding: .utf8),
              let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(value, 0) == 0
    }

    static func main() async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        await sendFilesProgress()
        await sendFilesCancel()
        await updateRemoteProgress()
    }

    static func sendFilesProgress() async {
        let gate = folder.appending(path: "send-gate"), pid = folder.appending(path: "send-pid")
        let records = "sending incremental file list\\na.bin\\n      1,024  10%%    1.00MB/s    0:00:09\\r" +
            "     4,300  42%%    1.00MB/s    0:00:06\\r"
        let rsync = script(records, "    10,240 100%%    1.00MB/s    0:00:10 (xfr#1)\\n", gate: gate, pid: pid)
        let shell = MachRemoteShell(ssh: MachSSH(address: "fake-mac", runner: runner(rsync: rsync, ssh: "")))
        var posts: [String] = []
        let coordinator = SendFilesCoordinator(shell: shell) { posts.append($0) }
        coordinator.sendFinderSelection([URL(fileURLWithPath: "/tmp/a.bin")])
        await waitUntil("rsync percent reaches SendFiles before rsync exits") { coordinator.progress == 42 }
        check(alive(pid) && coordinator.isRunning, "progress arrived while rsync was still running")
        FileManager.default.createFile(atPath: gate.path, contents: nil)
        await coordinator.waitForCompletion()
        check(coordinator.report == .init(sent: 1, failed: 0, outcome: .recent), "transfer completes")
        check(coordinator.progress == 100 && posts == ["Files sent to the remote Mac."], "one final report")
        print("PASS: Send Files updates its percent from rsync \\r records while rsync runs")
    }

    static func sendFilesCancel() async {
        let gate = folder.appending(path: "cancel-gate"), pid = folder.appending(path: "cancel-pid")
        let rsync = script("     1,024  10%%    1.00MB/s    0:00:09\\r", "", gate: gate, pid: pid)
        let shell = MachRemoteShell(ssh: MachSSH(address: "fake-mac", runner: runner(rsync: rsync, ssh: "")))
        let coordinator = SendFilesCoordinator(shell: shell) { _ in }
        coordinator.sendFinderSelection([URL(fileURLWithPath: "/tmp/a.bin")])
        await waitUntil("streamed progress before cancel") { coordinator.progress == 10 }
        coordinator.cancel()
        await coordinator.waitForCompletion()
        check(coordinator.report?.outcome == .cancelled, "cancel reports cancelled")
        await waitUntil("cancel stops the rsync child") { !alive(pid) }
        check(!FileManager.default.fileExists(atPath: gate.path), "the child stopped without its gate")
        print("PASS: cancelling Send Files stops the streaming child")
    }

    static func updateRemoteProgress() async {
        let gate = folder.appending(path: "update-gate"), pid = folder.appending(path: "update-pid")
        let ssh = script("── Homebrew\\nupgrading 3 formulae\\n", "Nothing to do.\\n", gate: gate, pid: pid)
        let shell = MachRemoteShell(ssh: MachSSH(address: "fake-mac", runner: runner(rsync: "", ssh: ssh)))
        var posts: [String] = []
        let coordinator = UpdateRemoteCoordinator(runner: shell, scriptPath: "/tools/update.sh") { posts.append($0) }
        coordinator.start()
        await waitUntil("remote script lines reach Update Remote before exit") { posts.count == 2 }
        check(alive(pid) && coordinator.isRunning, "lines arrived while ssh was still running")
        check(coordinator.progress.step == "Homebrew" && posts == ["── Homebrew", "upgrading 3 formulae"],
              "step and lines in order: \(posts)")
        FileManager.default.createFile(atPath: gate.path, contents: nil)
        await waitUntil("update finishes") { !coordinator.isRunning }
        check(coordinator.result == .nothingToDo, "final result from the full output")
        check(posts == ["── Homebrew", "upgrading 3 formulae", "Nothing to do.", "Remote Mac is up to date."],
              "each line delivered once, in order: \(posts)")
        print("PASS: Update Remote shows each remote line as it arrives, once and in order")
    }
}
