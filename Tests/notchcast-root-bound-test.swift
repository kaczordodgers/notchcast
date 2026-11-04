// notchcast-sources: -parse-as-library Tinycast/Features/Notchcast/Root/*.swift Tinycast/Platform/ProcessExit.swift
import Foundation

private final class StuckProcess: Process, @unchecked Sendable {
    override var isRunning: Bool { true }
    override func terminate() {}
}

@main
struct RootBoundTest {
    static func main() async throws {
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 6)
            print("FAIL: never-exiting child blocked return beyond 6 seconds")
            exit(1)
        }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await RootHelperClient().run(.ping, process: StuckProcess(), exit: ProcessExit(),
                                                output: Pipe(), timeout: .milliseconds(50))
            preconditionFailure("Expected timeout")
        } catch RootHelperClient.Failure.timedOut {}
        precondition(start.duration(to: clock.now) < .milliseconds(500))
        print("PASS: never-exiting child times out within 500ms")
        do {
            _ = try await RootHelperClient().run(.ping)
            preconditionFailure("Started a root tool while an abandoned one still runs")
        } catch RootHelperClient.Failure.timedOut {}
        print("PASS: no new root tool starts while an abandoned one runs")
        let task = Task {
            _ = try await RootHelperClient().run(.ping, process: StuckProcess(), exit: ProcessExit(),
                                                output: Pipe(), timeout: .seconds(60))
        }
        try await Task.sleep(for: .milliseconds(20))
        let cancelled = clock.now
        task.cancel()
        do {
            try await task.value
            preconditionFailure("Expected cancellation")
        } catch is CancellationError {}
        precondition(cancelled.duration(to: clock.now) < .milliseconds(500))
        print("PASS: cancellation returns within 500ms")
        let shutdown = clock.now
        await RootWait.drainForTermination {
            try? await RootHelperClient.wait(for: StuckProcess(), exit: ProcessExit(), timeout: .seconds(60))
        }
        precondition(shutdown.duration(to: clock.now) < .milliseconds(3500))
        print("PASS: termination root drain returns within 3.5 seconds")
    }
}
