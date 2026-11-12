// notchcast-sources: Tinycast/Features/Notchcast/Jobs/*.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Service/CommandProcessRunner.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Service/CatalogShellCommandRunner.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Model/HostCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/DownloadTool.swift
// notchcast-kit: platform
import Darwin
import Foundation

@main struct CommandProcessTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appending(path: "fake.sh")
        let pidFile = root.appending(path: "grandchild")
        try "sleep 120 &\necho $! > \"$1\"\nwait\n".write(to: script, atomically: true, encoding: .utf8)
        let task = Task {
            try await CommandProcessRunner.run(.init(executable: "/bin/sh", arguments: [script.path, pidFile.path],
                                                     workingDirectory: root.path))
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while !FileManager.default.fileExists(atPath: pidFile.path) {
            precondition(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancellation expected") } catch is CancellationError {}
        for _ in 0..<100 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(kill(pid, 0) != 0)
        let path = try await CommandProcessRunner.run(.init(
            executable: "/usr/bin/env", arguments: ["sh", "-c", "echo $PATH"], workingDirectory: nil))
        precondition(String(bytes: path.standardOutput, encoding: .utf8)?
            .hasPrefix("/opt/homebrew/bin:/usr/local/bin:") == true, "env finds Homebrew tools before /usr/bin")
        let output = try await CommandProcessRunner.run(.init(executable: "/bin/sh",
            arguments: ["-c", "pwd; printf 'error output' >&2; exit 7"], workingDirectory: root.path))
        precondition(output.exitStatus == 7, "Expected exit 7, got \(output.exitStatus)")
        let directory = String(bytes: output.standardOutput, encoding: .utf8)!
            .trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(URL(fileURLWithPath: directory).resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path,
            "Working directory \(directory.debugDescription), expected \(root.resolvingSymlinksInPath().path.debugDescription)")
        precondition(output.standardError == Data("error output".utf8), "stderr must be captured separately")
        let longOutput = try await CommandProcessRunner.run(.init(executable: "/bin/sh",
            arguments: ["-c", "printf 'prefix%s' '" + String(repeating: "x", count: 70_000)
                + "'; printf 'prefix%s' '" + String(repeating: "y", count: 70_000) + "' >&2"], workingDirectory: nil))
        precondition(longOutput.standardOutput == Data(String(repeating: "x", count: 65_536).utf8))
        precondition(longOutput.standardError == Data(String(repeating: "y", count: 65_536).utf8))
        let signaled = try await CommandProcessRunner.run(.init(executable: "/bin/sh",
            arguments: ["-c", "kill -TERM $$"], workingDirectory: nil))
        precondition(signaled.exitStatus == 128 + SIGTERM)
        let timedPIDFile = root.appending(path: "timed-grandchild")
        let started = ContinuousClock.now
        do {
            _ = try await CommandProcessRunner.run(.init(executable: "/bin/sh",
                arguments: [script.path, timedPIDFile.path], workingDirectory: root.path, timeout: .seconds(1)))
            preconditionFailure("Timeout expected")
        } catch ProcessRunner.Failure.timedOut {}
        precondition(ContinuousClock.now - started < .seconds(10), "Timeout must stop a long command")
        let timedPID = Int32(try String(contentsOf: timedPIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        for _ in 0..<100 where kill(timedPID, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(kill(timedPID, 0) != 0, "Timeout must stop grandchildren")
        print("Command cancellation, timeout, process groups, output, directory and PATH passed")
    }
}
