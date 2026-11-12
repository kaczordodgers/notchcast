import Foundation
import Synchronization

final class ChildProcess: Sendable {
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
            outputTail: 65_536, cleansGroupOnExit: true, killsOnQuit: true)
    }

    func run(onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> DownloadProcessResult {
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
            if state.withLock({ $0.cancelled }) { throw CancellationError() }
            return DownloadProcessResult(status: output.signaled ? 128 + output.status : output.status,
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
