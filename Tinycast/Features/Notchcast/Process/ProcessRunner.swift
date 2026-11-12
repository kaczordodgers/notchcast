import Darwin
import Foundation
import Synchronization

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
        var outputTail: Int?
        var onLine: (@Sendable (String) -> Void)?
        var cleansGroupOnExit = false
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
        return try await start(request).output()
    }

    struct Running: Sendable {
        fileprivate let job: Job
        private let completion: Task<Output, any Error>

        fileprivate init(job: Job, exit: ProcessExit) {
            self.job = job
            completion = Task.detached {
                defer { job.dispose() }
                await withCheckedContinuation { continuation in
                    Thread.detachNewThread { @Sendable in
                        exit.wait()
                        job.drain()
                        continuation.resume()
                    }
                }
                return try job.finish()
            }
        }

        var processIdentifier: Int32 { job.processIdentifier }
        var isRunning: Bool { job.isRunning }
        func cancel() { job.stop(.cancelled) }
        func terminate() { job.terminate() }
        func output() async throws -> Output {
            try await withTaskCancellationHandler { try await completion.value } onCancel: { cancel() }
        }
    }

    static func start(_ request: Request) throws -> Running {
        let job = try Job(request)
        do { return try Running(job: job, exit: job.launch()) } catch {
            job.dispose()
            throw error
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
        job.drain()
        return try job.finish()
    }

    fileprivate enum Stop { case cancelled, timedOut }

    fileprivate final class Job: Sendable {
        private struct State {
            var process: Process
            var stop: Stop?
            var timers: [DispatchWorkItem] = []
            var drained = false
            var drainDeadline: ContinuousClock.Instant?
        }

        private let request: Request
        private let folder: URL
        private let stdoutFile: URL
        private let stderrFile: URL
        private let handles: [FileHandle]
        private let state: Mutex<State>
        private let stdoutStream: ProcessOutputStream?
        private let stderrStream: ProcessOutputStream?

        var isRunning: Bool { state.withLock { $0.process.isRunning } }
        var processIdentifier: Int32 { state.withLock { $0.process.processIdentifier } }

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
                let stdoutStream = request.outputTail != nil || request.onLine != nil
                    ? ProcessOutputStream(limit: request.outputTail, onLine: request.onLine) : nil
                let stderrStream = request.outputTail != nil && { if case .capture = request.stderr { true } else { false } }()
                    ? ProcessOutputStream(limit: request.outputTail) : nil
                let stdout = try stdoutStream?.pipe.fileHandleForWriting ?? Self.create(stdoutFile)
                handles.append(stdout)
                process.standardOutput = stdout
                switch request.stderr {
                case .discard: process.standardError = FileHandle.nullDevice
                case .merge: process.standardError = stdout
                case .capture:
                    let stderr = try stderrStream?.pipe.fileHandleForWriting ?? Self.create(stderrFile)
                    handles.append(stderr)
                    process.standardError = stderr
                }
                self.request = request
                self.folder = folder
                self.stdoutFile = stdoutFile
                self.stderrFile = stderrFile
                self.handles = handles
                self.stdoutStream = stdoutStream
                self.stderrStream = stderrStream
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
                for stream in [stdoutStream, stderrStream].compactMap({ $0 }) {
                    try? stream.pipe.fileHandleForWriting.close()
                    stream.start { self.state.withLock { $0.drainDeadline } }
                }
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
                guard state.stop == nil, !state.drained else { return }
                state.stop = reason
                let pid = state.process.processIdentifier
                let target = request.stopsGroup ? -pid : pid
                kill(target, request.stopLadder.first)
                state.timers += request.stopLadder.escalate { signal in
                    self.state.withLock { state in
                        if !state.drained { kill(target, signal) }
                    }
                }
            }
        }

        func terminate() {
            state.withLock { state in
                guard !state.drained else { return }
                state.stop = .cancelled
                let pid = state.process.processIdentifier
                kill(request.stopsGroup ? -pid : pid, SIGKILL)
            }
        }

        func drain() {
            state.withLock { state in
                if request.stopsGroup, request.cleansGroupOnExit || state.stop != nil {
                    kill(-state.process.processIdentifier, SIGKILL)
                }
                state.drainDeadline = .now + .milliseconds(250)
            }
            stdoutStream?.wait()
            stderrStream?.wait()
            state.withLock { $0.drained = true; $0.timers.forEach { $0.cancel() } }
        }

        func finish() throws -> Output {
            let (stop, status, signaled) = state.withLock {
                ($0.stop, $0.process.terminationStatus,
                 $0.process.terminationReason == .uncaughtSignal)
            }
            if stop == .timedOut { throw Failure.timedOut }
            try Task.checkCancellation()
            if stop == .cancelled { throw CancellationError() }
            let stdout = try stdoutStream?.data ?? Self.read(stdoutFile, limit: request.outputLimit, failing: true)
            if request.outputTail == nil, stdout.count > request.outputLimit { throw Failure.outputLimit }
            let stderr = if case .capture(let limit) = request.stderr {
                try stderrStream?.data ?? Self.read(stderrFile, limit: limit, failing: false)
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

nonisolated final class ProcessOutputStream: Sendable {
    let pipe = Pipe()
    private let limit: Int?
    private let onLine: (@Sendable (String) -> Void)?
    private let captured = Mutex(Data())
    private let readers = DispatchGroup()

    init(limit: Int?, onLine: (@Sendable (String) -> Void)? = nil) {
        self.limit = limit
        self.onLine = onLine
    }
    var data: Data { captured.withLock { $0 } }
    func start(deadline: @escaping @Sendable () -> ContinuousClock.Instant?) {
        readers.enter()
        Thread.detachNewThread { @Sendable in
            defer { self.readers.leave(); try? self.pipe.fileHandleForReading.close() }
            let descriptor = self.pipe.fileHandleForReading.fileDescriptor
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 8192)
            while deadline().map({ ContinuousClock.now < $0 }) ?? true {
                var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&event, 1, 50)
                if ready < 0 && errno == EINTR { continue }
                if ready == 0 { continue }
                guard ready > 0 else { break }
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                self.captured.withLock {
                    $0.append(contentsOf: buffer.prefix(count))
                    if let limit = self.limit { Self.trim(&$0, limit: limit) }
                }
                if let onLine = self.onLine {
                    pending.append(contentsOf: buffer.prefix(count))
                    while let newline = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                        let line = String(bytes: pending[..<newline], encoding: .utf8) ?? ""
                        pending.removeSubrange(...newline)
                        if !line.isEmpty { onLine(line) }
                    }
                    Self.trim(&pending, limit: 65_536)
                }
            }
            if let onLine = self.onLine, !pending.isEmpty {
                onLine(String(bytes: pending, encoding: .utf8) ?? "")
            }
        }
    }
    func wait() { readers.wait() }
    private static func trim(_ data: inout Data, limit: Int) {
        if data.count > limit { data.removeFirst(data.count - limit) }
        while let first = data.first, first & 0xC0 == 0x80 { data.removeFirst() }
    }
}

private extension Duration {
    nonisolated var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
