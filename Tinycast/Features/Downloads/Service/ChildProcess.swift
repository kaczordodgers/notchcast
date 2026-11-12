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
                ?? String(localized: "Tool exited with status \(result.status).", table: "Notchcast")
        }
    }

    private struct State {
        var started = false
        var running: ProcessRunner.Running?
        var cancelled = false
    }

    private let request: ProcessRunner.Request
    private let state = Mutex(State())

    init(
        executable: URL, arguments: [String],
        environment: [String: String] = DownloadToolLookup().environment,
        workingDirectory: URL? = nil
    ) {
        request = ProcessRunner.Request(executable: executable, arguments: arguments,
            environment: environment, directory: workingDirectory, stderr: .capture(limit: 65_536),
            stopLadder: .terminating(grace: .milliseconds(250)), stopsGroup: true,
            outputTail: 65_536, cleansGroupOnExit: true)
    }

    func run(onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Result {
        let center = NotificationCenter.default
        let token = NotificationToken(center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [self] _ in state.withLock { $0.cancelled = true; $0.running?.terminate() } }, center: center)
        defer { withExtendedLifetime(token) {} }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let running = try state.withLock { state in
                guard !state.cancelled else { throw CancellationError() }
                guard !state.started else { throw POSIXError(.EINVAL) }
                state.started = true
                var request = self.request
                request.onLine = onLine
                let running = try ProcessRunner.start(request)
                state.running = running
                return running
            }
            defer { state.withLock { $0.running = nil } }
            let output = try await running.output()
            return Result(status: output.signaled ? 128 + output.status : output.status,
                output: String(bytes: output.stdout, encoding: .utf8) ?? "",
                errors: String(bytes: output.stderr, encoding: .utf8) ?? "")
        } onCancel: { cancel() }
    }

    func cancel() {
        state.withLock { state in
            state.cancelled = true
            state.running?.cancel()
        }
    }
}
