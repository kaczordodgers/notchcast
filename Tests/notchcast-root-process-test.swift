// notchcast-kit: root platform
// notchcast-sources: -parse-as-library
// notchcast-reads: notchcast/root/*.swift notchcast/root/install.sh
// notchcast-reads: Tinycast/Features/SystemMonitor/Model/SMCValue.swift Tinycast/Features/SystemTools/Model/TouchIDPolicy.swift
import Darwin
import Foundation

@main struct RootProcessTest {
    static func main() async throws {
        try await validateProcessLifetime()
        print("PASS: root process lifetime, timeouts and cancellation")
    }

    private static func validateProcessLifetime() async throws {
        let fast = sleeper("0.01")
        let fastExit = try fast.runObservingExit()
        try await RootHelperClient.wait(for: fast, exit: fastExit, timeout: .seconds(1))
        precondition(!fast.isRunning && fast.terminationStatus == 0)

        let slow = sleeper("10")
        let slowExit = try slow.runObservingExit()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await RootHelperClient.wait(for: slow, exit: slowExit, timeout: .milliseconds(50))
            preconditionFailure("A slow helper must time out")
        } catch RootHelperClient.Failure.timedOut {
            precondition(start.duration(to: clock.now) < .seconds(2))
        }

        let cancelled = sleeper("10")
        let cancelledExit = try cancelled.runObservingExit()
        let task = Task {
            try await RootHelperClient.wait(for: cancelled, exit: cancelledExit, timeout: .seconds(3))
        }
        task.cancel()
        do {
            try await task.value
            preconditionFailure("Cancellation must propagate")
        } catch is CancellationError {
        }
    }

    private static func sleeper(_ seconds: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
