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
import AppKit
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
            executable: "/usr/bin/env", arguments: ["sh", "-c", "echo $PATH; echo LANG=$LANG; echo LC_ALL=$LC_ALL"],
            workingDirectory: nil))
        precondition(String(bytes: path.standardOutput, encoding: .utf8)?
            .hasPrefix("/usr/bin:/opt/homebrew/bin:/usr/local/bin:") == true, "Commands use the shared executable environment")
        precondition(String(bytes: path.standardOutput, encoding: .utf8)?
            .hasSuffix("\nLANG=en_US.UTF-8\nLC_ALL=en_US.UTF-8\n") == true, "Commands preserve the UTF-8 locale")
        let output = try await CommandProcessRunner.run(.init(executable: "/bin/sh",
            arguments: ["-c", "pwd; printf 'error output' >&2; exit 7"], workingDirectory: root.path))
        precondition(output.exitStatus == 7, "Expected exit 7, got \(output.exitStatus)")
        let directory = String(bytes: output.standardOutput, encoding: .utf8)!
            .trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(URL(fileURLWithPath: directory).resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path,
            "Working directory \(directory.debugDescription), expected \(root.resolvingSymlinksInPath().path.debugDescription)")
        precondition(output.standardError == Data("error output".utf8), "stderr must be captured separately")
        let outputMarker = "START-\(UUID().uuidString)"
        let wrote = root.appending(path: "long-wrote"), release = root.appending(path: "long-release")
        let longStart = Date().addingTimeInterval(-1)
        let long = Task { try await CommandProcessRunner.run(.init(executable: "/bin/sh", arguments: ["-c",
            "printf '\(outputMarker)'; dd if=/dev/zero bs=1048576 count=8 2>/dev/null | tr '\\000' x; printf END; "
                + "printf '\(outputMarker)' >&2; dd if=/dev/zero bs=1048576 count=8 2>/dev/null | tr '\\000' y >&2; "
                + "printf END >&2; : > \"$1\"; while [ ! -e \"$2\" ]; do sleep .01; done",
            "sh", wrote.path, release.path], workingDirectory: nil)) }
        let longDeadline = ContinuousClock.now + .seconds(30)
        while !FileManager.default.fileExists(atPath: wrote.path) {
            precondition(ContinuousClock.now < longDeadline, "Long command must finish writing")
            try await Task.sleep(for: .milliseconds(10))
        }
        let temp = FileManager.default.temporaryDirectory
        let spooled = try FileManager.default.contentsOfDirectory(atPath: temp.path)
            .filter { $0.hasPrefix("notchcast-run-") }
            .filter { run in ((try? FileManager.default.attributesOfItem(atPath: temp.appending(path: run).path))?[
                .creationDate] as? Date).map { $0 >= longStart } ?? false }
            .flatMap { run in ["out", "err"].map { temp.appending(path: "\(run)/\($0)").path } }
            .filter {
                (FileHandle(forReadingAtPath: $0)?.readData(ofLength: outputMarker.utf8.count))
                    .map { $0 == Data(outputMarker.utf8) } ?? false
            }
            .compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int }
            .reduce(0, +)
        precondition(spooled < 1_048_576, "A running command must not spool its whole output (\(spooled) bytes)")
        try Data().write(to: release)
        let longOutput = try await long.value
        precondition(longOutput.standardOutput == Data((String(repeating: "x", count: 65_533) + "END").utf8))
        precondition(longOutput.standardError == Data((String(repeating: "y", count: 65_533) + "END").utf8))
        let signaled = try await CommandProcessRunner.run(.init(executable: "/bin/sh",
            arguments: ["-c", "kill -TERM $$"], workingDirectory: nil))
        precondition(signaled.exitStatus == 128 + SIGTERM)
        let timedPIDFile = root.appending(path: "timed-grandchild")
        let started = ContinuousClock.now
        let timedOut = try await CommandProcessRunner.run(.init(executable: "/bin/sh",
            arguments: [script.path, timedPIDFile.path], workingDirectory: root.path, timeout: .seconds(1)))
        precondition(!timedOut.succeeded && timedOut.exitStatus == 143, "Timeout must return a failed result")
        precondition(ContinuousClock.now - started < .seconds(10), "Timeout must stop a long command")
        let timedPID = Int32(try String(contentsOf: timedPIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        for _ in 0..<100 where kill(timedPID, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(kill(timedPID, 0) != 0, "Timeout must stop grandchildren")
        let quitPIDFile = root.appending(path: "quit-group")
        let childPIDFile = root.appending(path: "quit-child")
        let quitting = Task {
            try await CommandProcessRunner.run(.init(executable: "/bin/sh", arguments: ["-c",
                "trap '' TERM; echo $$ > \"$1\"; "
                    + "/bin/sh -c 'trap \"\" TERM; echo $$ > \"$1\"; exec sleep 120' sh \"$2\" & wait",
                "sh", quitPIDFile.path, childPIDFile.path], workingDirectory: root.path, timeout: .seconds(5)))
        }
        let quitDeadline = ContinuousClock.now + .seconds(10)
        while !FileManager.default.fileExists(atPath: childPIDFile.path) {
            precondition(ContinuousClock.now < quitDeadline, "Quit command must start its TERM-ignoring child")
            try await Task.sleep(for: .milliseconds(10))
        }
        let group = Int32(try String(contentsOf: quitPIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        let child = Int32(try String(contentsOf: childPIDFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        do { _ = try await quitting.value; preconditionFailure("Quit must cancel the command") } catch is CancellationError {}
        for _ in 0..<100 where kill(-group, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(kill(-group, 0) == -1 && errno == ESRCH, "Quit must kill the entire process group")
        precondition(kill(child, 0) == -1 && errno == ESRCH, "Quit must kill the TERM-ignoring child")
        print("Command cancellation, timeout, quit process groups, 64 KB output tails, directory and PATH passed")
    }
}
