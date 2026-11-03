import Foundation
import Synchronization

nonisolated struct SpeedTestRunner: Sendable {
    func run() async throws -> SpeedTestResult {
        let job = Job()
        return try await withTaskCancellationHandler {
            let data = try await job.run()
            try Task.checkCancellation()
            return try SpeedTestResult.parse(data)
        } onCancel: { job.cancel() }
    }

    private final class Job: Sendable {
        private struct State {
            var process: Process?
            var cancelled = false
        }

        private let state = Mutex(State())

        func cancel() {
            state.withLock {
                $0.cancelled = true
                if let process = $0.process, process.isRunning { process.terminate() }
            }
        }

        @concurrent func run() async throws -> Data {
            try runBlocking()
        }

        private func runBlocking() throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
            process.arguments = ["-c"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            let exited = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in exited.signal() }
            try state.withLock {
                if $0.cancelled { throw CancellationError() }
                try process.run()
                $0.process = process
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            exited.wait()
            try state.withLock {
                $0.process = nil
                if $0.cancelled { throw CancellationError() }
            }
            guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
            return data
        }
    }
}
