import Darwin
import Foundation
import Synchronization

/// Runs one program to its exit; a timeout or cancellation stops it, and output is read from files.
nonisolated enum ProcessRunner {
    struct Request: Sendable {
        enum ErrorOutput: Sendable { case discard, capture(limit: Int), merge }

        var executable: URL
        var arguments: [String] = []
        var environment: [String: String]?
        var directory: URL?
        var input: Data?
        var stderr = ErrorOutput.discard
        var timeout: Duration?
        var outputLimit = Int.max
        var stopLadder = StopLadder.terminating()
        /// Stops the children the program started too; `Process` makes every child its own group leader.
        var stopsGroup = false
    }

    /// The signals a stopped child gets: `first` at once, each later one at its delay from the stop.
    struct StopLadder: Sendable {
        struct Rung: Sendable {
            let signal: Int32
            let after: Duration
        }

        let first: Int32
        let later: [Rung]

        static func terminating(_ signal: Int32 = SIGTERM, grace: Duration = .seconds(2)) -> StopLadder {
            StopLadder(first: signal, later: [Rung(signal: SIGKILL, after: grace)])
        }

        static func interrupting(kill: Duration) -> StopLadder {
            StopLadder(first: SIGINT, later: [Rung(signal: SIGTERM, after: .seconds(1)), Rung(signal: SIGKILL, after: kill)])
        }

        func signal(after elapsed: Duration) -> Int32 {
            later.last { $0.after < elapsed }?.signal ?? first
        }

        @discardableResult
        func escalate(_ send: @escaping @Sendable (Int32) -> Void) -> [DispatchWorkItem] {
            later.map { rung in
                let item = DispatchWorkItem { send(rung.signal) }
                DispatchQueue.global().asyncAfter(deadline: .now() + rung.after.seconds, execute: item)
                return item
            }
        }
    }

    struct Output: Sendable {
        let status: Int32
        /// `status` is then the signal's number, not an exit code.
        let signaled: Bool
        let stdout: Data
        let stderr: Data
    }

    enum Failure: Error, Equatable { case timedOut, outputLimit }

    @concurrent
    static func run(_ request: Request) async throws -> Output {
        try Task.checkCancellation()
        let job = try Job(request)
        defer { job.dispose() }
        let exit = try job.launch()
        return try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Thread.detachNewThread { @Sendable in
                    exit.wait()
                    continuation.resume()
                }
            }
            return try job.finish()
        } onCancel: {
            job.stop(.cancelled)
        }
    }

    /// For callers whose own contract is synchronous; cancellation is noticed within 10 ms.
    static func runBlocking(_ request: Request) throws -> Output {
        try Task.checkCancellation()
        let job = try Job(request)
        defer { job.dispose() }
        let exit = try job.launch()
        while job.isRunning {
            if Task.isCancelled { job.stop(.cancelled) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        exit.wait()
        return try job.finish()
    }

    private enum Stop { case cancelled, timedOut }

    private final class Job: Sendable {
        private struct State {
            var process: Process
            var stop: Stop?
            var timers: [DispatchWorkItem] = []
        }

        private let request: Request
        private let folder: URL
        private let stdoutFile: URL
        private let stderrFile: URL
        private let handles: [FileHandle]
        private let state: Mutex<State>

        var isRunning: Bool { state.withLock { $0.process.isRunning } }

        init(_ request: Request) throws {
            let files = FileManager.default
            let folder = files.temporaryDirectory.appending(path: "notchcast-run-\(UUID().uuidString)")
            try files.createDirectory(at: folder, withIntermediateDirectories: false,
                                      attributes: [.posixPermissions: 0o700])
            var handles: [FileHandle] = []
            do {
                let process = Process()
                process.executableURL = request.executable
                process.arguments = request.arguments
                process.environment = request.environment
                process.currentDirectoryURL = request.directory
                process.standardInput = FileHandle.nullDevice
                if let input = request.input {
                    let file = folder.appending(path: "in")
                    try input.write(to: file)
                    let handle = try FileHandle(forReadingFrom: file)
                    handles.append(handle)
                    process.standardInput = handle
                }
                let stdoutFile = folder.appending(path: "out")
                let stderrFile = folder.appending(path: "err")
                let stdout = try Self.create(stdoutFile)
                handles.append(stdout)
                process.standardOutput = stdout
                switch request.stderr {
                case .discard: process.standardError = FileHandle.nullDevice
                case .merge: process.standardError = stdout
                case .capture:
                    let stderr = try Self.create(stderrFile)
                    handles.append(stderr)
                    process.standardError = stderr
                }
                self.request = request
                self.folder = folder
                self.stdoutFile = stdoutFile
                self.stderrFile = stderrFile
                self.handles = handles
                state = Mutex(State(process: process))
            } catch {
                try? files.removeItem(at: folder)
                throw error
            }
        }

        private static func create(_ file: URL) throws -> FileHandle {
            guard FileManager.default.createFile(atPath: file.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return try FileHandle(forWritingTo: file)
        }

        func launch() throws -> ProcessExit {
            try state.withLock { state in
                let exit = try state.process.runObservingExit()
                if let timeout = request.timeout {
                    let timer = DispatchWorkItem { @Sendable in self.stop(.timedOut) }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout.seconds, execute: timer)
                    state.timers.append(timer)
                }
                return exit
            }
        }

        func stop(_ reason: Stop) {
            state.withLock { state in
                guard state.stop == nil, state.process.isRunning else { return }
                state.stop = reason
                let pid = state.process.processIdentifier
                let target = request.stopsGroup ? -pid : pid
                kill(target, request.stopLadder.first)
                state.timers += request.stopLadder.escalate { signal in
                    self.state.withLock { state in
                        if state.process.isRunning { kill(target, signal) }
                    }
                }
            }
        }

        func finish() throws -> Output {
            let (stop, pid, status, signaled) = state.withLock {
                ($0.stop, $0.process.processIdentifier, $0.process.terminationStatus,
                 $0.process.terminationReason == .uncaughtSignal)
            }
            // Leader exited: a child that ignored the stop signal gets SIGKILL now, no grace.
            if stop != nil, request.stopsGroup { kill(-pid, SIGKILL) }
            if stop == .timedOut { throw Failure.timedOut }
            try Task.checkCancellation()
            if stop == .cancelled { throw CancellationError() }
            let stdout = try Self.read(stdoutFile, limit: request.outputLimit, failing: true)
            let stderr = if case .capture(let limit) = request.stderr {
                try Self.read(stderrFile, limit: limit, failing: false)
            } else { Data() }
            return Output(status: status, signaled: signaled, stdout: stdout, stderr: stderr)
        }

        func dispose() {
            state.withLock { state in state.timers.forEach { $0.cancel() } }
            for handle in handles { try? handle.close() }
            try? FileManager.default.removeItem(at: folder)
        }

        private static func read(_ file: URL, limit: Int, failing: Bool) throws -> Data {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            if failing, size > UInt64(limit) { throw Failure.outputLimit }
            try handle.seek(toOffset: 0)
            return try handle.read(upToCount: Int(min(size, UInt64(limit)))) ?? Data()
        }
    }
}

private extension Duration {
    nonisolated var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
