import Foundation
import Synchronization

extension DictationCapture {
    nonisolated static func startBounded(
        timeout: Duration = .seconds(5),
        start: @escaping @Sendable () -> Bool, stop: @escaping @Sendable () -> Void
    ) async throws {
        let attempt = StartAttempt()
        let running = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard attempt.install(continuation) else { return }
                let deadline = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    attempt.complete(.failure(Failure.coreAudioUnresponsive))
                }
                attempt.setDeadline(deadline)
                // A blocked driver cannot be cancelled; late success closes its own session.
                DispatchQueue.global().async {
                    let running = start()
                    if !attempt.complete(.success(running)), running { stop() }
                }
            }
        } onCancel: {
            attempt.complete(.failure(CancellationError()))
        }
        guard running else { throw Failure.captureUnavailable }
    }

    private final class StartAttempt: Sendable {
        private struct State {
            var continuation: CheckedContinuation<Bool, any Error>?
            var result: Result<Bool, any Error>?
            var deadline: Task<Void, Never>?
        }

        private let state = Mutex(State())

        func install(_ continuation: CheckedContinuation<Bool, any Error>) -> Bool {
            let result = state.withLock { state -> Result<Bool, any Error>? in
                if let result = state.result { return result }
                state.continuation = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
            return result == nil
        }

        func setDeadline(_ deadline: Task<Void, Never>) {
            let completed = state.withLock { state in
                guard state.result == nil else { return true }
                state.deadline = deadline
                return false
            }
            if completed { deadline.cancel() }
        }

        @discardableResult
        func complete(_ result: Result<Bool, any Error>) -> Bool {
            let completion = state.withLock { state -> (Bool, CheckedContinuation<Bool, any Error>?) in
                guard state.result == nil else { return (false, nil) }
                state.result = result
                let continuation = state.continuation
                state.continuation = nil
                state.deadline?.cancel()
                state.deadline = nil
                return (true, continuation)
            }
            completion.1?.resume(with: result)
            return completion.0
        }
    }
}
