import Darwin
import Foundation

@main
struct CleanProcessTest {
    static func main() async throws {
        let root = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager().removeItem(at: root) }
        let marker = root.appendingPathComponent("escaped")
        let script = "(sleep 1; echo escaped > \"$1\") & wait"
        do {
            _ = try await CleanProcessRunner.execute(URL(fileURLWithPath: "/bin/sh"),
                ["-c", script, "test", marker.path], timeout: 0.1)
            preconditionFailure("Expected timeout")
        } catch let error as POSIXError { precondition(error.code == .ETIMEDOUT) }
        let task = Task {
            try await CleanProcessRunner.execute(URL(fileURLWithPath: "/bin/sh"),
                ["-c", script, "test", marker.path], timeout: 180)
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancelledAt = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Expected cancellation") } catch is CancellationError {}
        precondition(ContinuousClock.now - cancelledAt < .milliseconds(500), "Cancellation was not prompt")
        try await Task.sleep(for: .seconds(2))
        precondition(!FileManager().fileExists(atPath: marker.path))
        let result = try await CleanProcessRunner.execute(URL(fileURLWithPath: "/bin/echo"), ["alive"], timeout: 2)
        precondition(result.code == 0 && result.output == "alive\n")
        print("PASS process-group timeout/prompt cancellation; unrelated invocation survives")
    }
}
