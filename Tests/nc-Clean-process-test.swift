// notchcast-sources: Tinycast/Features/Clean/CleanTool.swift Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
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
        print("PASS process-group timeout/prompt cancellation; a killed tool never reads as exit code 1")
    }
}
