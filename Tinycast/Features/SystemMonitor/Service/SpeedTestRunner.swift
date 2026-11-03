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
            var continuation: CheckedContinuation<Data, any Error>?
            var data: Data?
            var status: Int32?
        }

        private let state = Mutex(State())

        func cancel() {
            state.withLock {
                $0.cancelled = true
                if let process = $0.process, process.isRunning { process.terminate() }
            }
        }

        func run() async throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
            process.arguments = ["-c", "-M", "30"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { process in
                self.state.withLock {
                    $0.status = process.terminationStatus
                    Self.finish(&$0)
                }
            }
            return try await withCheckedThrowingContinuation { continuation in
                state.withLock {
                    guard !$0.cancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                        return
                    }
                    $0.process = process
                    $0.continuation = continuation
                    DispatchQueue.global(qos: .utility).async {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        try? pipe.fileHandleForReading.close()
                        self.state.withLock {
                            $0.data = data
                            Self.finish(&$0)
                        }
                    }
                }
            }
        }

        private static func finish(_ state: inout State) {
            guard let status = state.status, let data = state.data,
                  let continuation = state.continuation else { return }
            state.process = nil
            state.continuation = nil
            if state.cancelled {
                continuation.resume(throwing: CancellationError())
            } else if status != 0 {
                continuation.resume(throwing: CocoaError(.executableRuntimeMismatch))
            } else {
                continuation.resume(returning: data)
            }
        }
    }
}
