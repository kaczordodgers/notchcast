// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/SendFiles/*.swift
import Foundation

@MainActor
final class FakeRemoteShell: RemoteShellRunning {
    var sshAlias = "remote-test"
    var calls: [(String, [String])] = []
    var copyStatuses: [Int32] = []
    var cancelCopy = false

    func run(_ executable: String, arguments: [String], output: @escaping @MainActor (String) -> Void)
        async throws -> SendFilesProcessResult {
        calls.append((executable, arguments))
        if executable == "/usr/bin/rsync" {
            output("  1,024 4")
            output("2% 1MB/s 0:00:01\r 2,048 100% 1MB/s 0:00:00\n")
            if cancelCopy { throw CancellationError() }
            return .init(status: copyStatuses.isEmpty ? 0 : copyStatuses.removeFirst(), output: "")
        }
        return .init(status: 0, output: "")
    }
}

// Runs the real commit script under macOS's default shell, where `status` is read-only.
func commitUnderZsh(in root: URL) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", SendFilesPlan.commit(staging: "stage", name: "a file")]
    process.currentDirectoryURL = root
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

@main
struct SendFilesTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("stage"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("stage/a file"))
        let committed = try commitUnderZsh(in: root)
        precondition(committed == 0)
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent("Downloads/a file").path))
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Downloads/a file.notchcast-claim").path))
        let source = URL(fileURLWithPath: "/tmp/a file's name")
        for (address, runs) in [("", false), ("-bad", false), ("host;echo bad", false), ("user@2001:db8::1", true)] {
            let fake = FakeRemoteShell()
            fake.sshAlias = address
            var notices: [String] = []
            let coordinator = SendFilesCoordinator(shell: fake, post: { notices.append($0) })
            coordinator.sendFinderSelection([source])
            await coordinator.waitForCompletion()
            precondition(fake.calls.isEmpty == !runs)
            if !runs {
                precondition(notices == [String(localized: "Set the remote Mac address in Settings")])
            }
        }
        precondition(SendFilesPlan.arguments(source: source, alias: "test", staging: "Downloads/.upload") == [
            "-a", "--safe-links", "--progress", "--timeout=30", "-e", "ssh -o BatchMode=yes", "--",
            "/tmp/a file's name", "test:'Downloads/.upload/'",
        ])
        precondition(SendFilesPlan.quote("a'b") == "'a'\\''b'")
        precondition(SendFilesPlan.percent(in: " 1,024 42% 1MB/s") == 42)
        precondition(SendFilesPlan.percent(in: "a file 42%") == nil)
        precondition(SendFilesPlan.percent(in: "1 101%") == nil)
        precondition(SendFilesPlan.percent(in: "1 0%") == 0)
        for status: Int32 in [0, 1, 23, 24, 255] {
            let shell = FakeRemoteShell()
            shell.copyStatuses = [0, status]
            var notices: [String] = []
            let coordinator = SendFilesCoordinator(shell: shell, post: { notices.append($0) })
            coordinator.sendFinderSelection([source, source])
            await coordinator.waitForCompletion()
            precondition(coordinator.report?.sent == (status == 0 ? 2 : 1))
            precondition(coordinator.report?.outcome == (status == 0 ? .recent : .needsAttention))
            precondition(coordinator.progress == 100)
            precondition(shell.calls.last?.1.last?.hasPrefix("rm -rf -- 'Downloads/.notchcast-upload-") == true)
            if status != 0 { precondition(notices.last?.contains("Nothing from the failed folder") == true) }
        }
        let shell = FakeRemoteShell()
        shell.cancelCopy = true
        let cancelled = SendFilesCoordinator(shell: shell, post: { _ in })
        cancelled.sendFinderSelection([source])
        await cancelled.waitForCompletion()
        precondition(cancelled.report?.outcome == .cancelled)
        precondition(shell.calls.last?.1.last?.hasPrefix("rm -rf") == true)
        let stopped = SendFilesCoordinator(shell: shell, post: { _ in })
        stopped.sendFinderSelection([source])
        stopped.cancel()
        await stopped.waitForCompletion()
        precondition(stopped.report?.outcome == .cancelled)
        print("Send files tests passed")
    }
}
