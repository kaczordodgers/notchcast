// notchcast-sources: Tinycast/Features/Clean/CleanTool.swift Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift Tinycast/Features/Clean/Model/CleanOptimizeRequest.swift
import Darwin
import Foundation

@main
struct CleanProcessTest {
    static func main() async throws {
        let root = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager().removeItem(at: root) }
        let marker = root.appendingPathComponent("escaped")
        let shell = URL(fileURLWithPath: "/bin/sh")
        let script = "(sleep 1; echo escaped > \"$1\") & wait"
        do {
            _ = try await CleanTool.run(shell, ["-c", script, "test", marker.path], timeout: 0.1)
            preconditionFailure("Expected timeout")
        } catch ProcessRunner.Failure.timedOut {}
        let task = Task {
            try await CleanTool.run(shell, ["-c", script, "test", marker.path], timeout: 180)
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancelledAt = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Expected cancellation") } catch is CancellationError {}
        precondition(ContinuousClock.now - cancelledAt < .milliseconds(500), "Cancellation was not prompt")
        try await Task.sleep(for: .seconds(2))
        precondition(!FileManager().fileExists(atPath: marker.path))
        let killed = try await CleanTool.run(shell, ["-c", "kill -HUP $$"], timeout: 2)
        precondition(killed.code == 128 + SIGHUP)
        let result = try await CleanTool.run(shell, ["-c", "echo alive; echo $GIT_TERMINAL_PROMPT >&2"], timeout: 2)
        precondition(result.code == 0 && result.output == "alive\n" && result.error == "0\n")
        let noise = "head -c \"$1\" /dev/zero | tr '\\0' x >&2"
        let cut = try await CleanTool.run(shell, ["-c", noise, "test", "1048577"], timeout: 10)
        precondition(cut.error.utf8.count == 1_048_576 + 12 && cut.error.hasSuffix("x\n[truncated]"))
        let whole = try await CleanTool.run(shell, ["-c", noise, "test", "1048576"], timeout: 10)
        precondition(whole.error.utf8.count == 1_048_576 && whole.error.hasSuffix("x"))
        let binary = try await CleanTool.run(shell, ["-c", "printf '\\377' >&2"], timeout: 2)
        precondition(binary.code == 0 && binary.error == "\u{FFFD}", "Invalid UTF-8 error output must not fail the run")
        let slow = root.appendingPathComponent("slow-tool")
        try "#!/bin/sh\nsleep 5\n".write(to: slow, atomically: true, encoding: .utf8)
        try FileManager().setAttributes([.posixPermissions: 0o755], ofItemAtPath: slow.path)
        let unknown = try await CleanTool.idle(root, recursive: true, tool: slow, timeout: 0.2)
        precondition(unknown == nil, "A timed-out lsof must read as an unknown state")
        let budget = try await CleanTool.optimize(CleanOptimizeRequest(executable: shell,
            arguments: ["-c", "sleep 5"], timeout: 0.2))
        precondition(budget == .timedOut, "A tool past its budget must report .timedOut, not throw")
        print("PASS process-group timeout/prompt cancellation; a killed tool never reads as exit code 1")
        print("PASS error output past 1 MiB is cut and marked; exactly 1 MiB is returned whole")
        print("PASS invalid UTF-8 error output decodes lossily; a timed-out tool is unknown or .timedOut")
    }
}
