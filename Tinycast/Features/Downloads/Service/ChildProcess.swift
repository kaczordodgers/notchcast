import AppKit
import Darwin
import Foundation
import Synchronization

final class ChildProcess: Sendable {
    struct Result: Sendable, Equatable {
        let status: Int32
        let output: String
        let errors: String
    }

    struct Failure: LocalizedError {
        let result: Result

        var errorDescription: String? {
            result.errors.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
                ?? String(localized: "Tool exited with status \(result.status).")
        }
    }

    private struct State {
        var started = false
        var processID: pid_t?
        var cancelledAt: UInt64?
    }

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let workingDirectory: URL?
    private let state = Mutex(State())

    init(
        executable: URL, arguments: [String],
        environment: [String: String] = DownloadToolLookup().environment,
        workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    func run(onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Result {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Swift.Result { try self.runBlocking(onLine: onLine) })
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        state.withLock { state in
            if state.cancelledAt == nil { state.cancelledAt = DispatchTime.now().uptimeNanoseconds }
            if let processID = state.processID { kill(-processID, SIGTERM) }
        }
    }

    private func terminateForQuit() {
        state.withLock { state in
            state.cancelledAt = 0
            guard let processID = state.processID else { return }
            kill(-processID, SIGTERM)
            kill(-processID, SIGKILL)
        }
    }

    private func runBlocking(onLine: @escaping @Sendable (String) -> Void) throws -> Result {
        let center = NotificationCenter.default
        let token = NotificationToken(center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [self] _ in terminateForQuit() }, center: center)
        defer { withExtendedLifetime(token) {} }
        let output = Pipe()
        let errors = Pipe()
        let processID = try state.withLock { state in
            guard state.cancelledAt == nil else { throw CancellationError() }
            guard !state.started else { throw POSIXError(.EINVAL) }
            state.started = true
            let processID = try launch(output: output, errors: errors)
            state.processID = processID
            return processID
        }
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        let outputFD = output.fileHandleForReading.fileDescriptor
        let errorFD = errors.fileHandleForReading.fileDescriptor
        _ = fcntl(outputFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(errorFD, F_SETFL, O_NONBLOCK)
        var stdout = Capture()
        var stderr = Capture()
        var status: Int32 = 0
        while true {
            stdout.read(from: outputFD, onLine: onLine)
            stderr.read(from: errorFD)
            let cancelledAt = state.withLock { $0.cancelledAt }
            if let cancelledAt {
                if DispatchTime.now().uptimeNanoseconds - cancelledAt >= 250_000_000 {
                    state.withLock { state in
                        kill(-processID, SIGKILL)
                        while waitpid(processID, &status, 0) < 0 && errno == EINTR {}
                        state.processID = nil
                    }
                    break
                }
            } else {
                var information = siginfo_t()
                if waitid(P_PID, id_t(processID), &information, WEXITED | WNOHANG | WNOWAIT) == 0,
                   information.si_pid == processID {
                    // Keep the leader unreaped until its group is dead, so its pid cannot be reused.
                    state.withLock { state in
                        kill(-processID, SIGTERM)
                        kill(-processID, SIGKILL)
                        while waitpid(processID, &status, 0) < 0 && errno == EINTR {}
                        state.processID = nil
                    }
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let cancelled = state.withLock { state in
            return state.cancelledAt != nil
        }
        stdout.read(from: outputFD, onLine: onLine)
        stderr.read(from: errorFD)
        stdout.finish(onLine: onLine)
        if cancelled { throw CancellationError() }
        let exitCode = status & 0x7F == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
        return Result(status: exitCode, output: stdout.text, errors: stderr.text)
    }

    private func launch(output: Pipe, errors: Pipe) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }
        var signals = sigset_t(0)
        sigemptyset(&signals)
        posix_spawnattr_setsigmask(&attributes, &signals)
        for signal in [SIGTERM, SIGINT, SIGPIPE, SIGHUP] { sigaddset(&signals, signal) }
        posix_spawnattr_setsigdefault(&attributes, &signals)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errors.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        if let workingDirectory { posix_spawn_file_actions_addchdir(&actions, workingDirectory.path) }
        let argv = CStringArray([executable.path] + arguments)
        let envp = CStringArray(environment.map { "\($0.key)=\($0.value)" })
        var processID: pid_t = 0
        let status = posix_spawn(&processID, executable.path, &actions, &attributes, argv.pointers, envp.pointers)
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO) }
        return processID
    }

    private struct Capture {
        private var tail = Data()
        private var pending = Data()
        var text: String { String(bytes: tail, encoding: .utf8) ?? "" }

        mutating func read(from descriptor: Int32, onLine: (@Sendable (String) -> Void)? = nil) {
            var buffer = [UInt8](repeating: 0, count: 8192)
            for _ in 0..<16 {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                tail.append(contentsOf: buffer.prefix(count))
                if tail.count > 65_536 { tail.removeFirst(tail.count - 65_536) }
                while let first = tail.first, first & 0xC0 == 0x80 { tail.removeFirst() }
                guard let onLine else { continue }
                pending.append(contentsOf: buffer.prefix(count))
                while let newline = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let line = String(bytes: pending[..<newline], encoding: .utf8) ?? ""
                    pending.removeSubrange(...newline)
                    if !line.isEmpty { onLine(line) }
                }
                if pending.count > 65_536 { pending.removeFirst(pending.count - 65_536) }
                while let first = pending.first, first & 0xC0 == 0x80 { pending.removeFirst() }
            }
        }

        mutating func finish(onLine: @Sendable (String) -> Void) {
            if !pending.isEmpty { onLine(String(bytes: pending, encoding: .utf8) ?? "") }
            pending.removeAll()
        }
    }

    private final class CStringArray {
        let pointers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        private let count: Int

        init(_ values: [String]) {
            count = values.count
            pointers = .allocate(capacity: count + 1)
            for (index, value) in values.enumerated() { pointers[index] = strdup(value) }
            pointers[count] = nil
        }

        deinit {
            for index in 0..<count { free(pointers[index]) }
            pointers.deallocate()
        }
    }
}
