import Foundation
import Synchronization

final class RootWait: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, any Error>?
        var result: Result<Void, any Error>?
    }

    private let state = Mutex(State())

    static func drainForTermination(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        try? await perform(timeout: .seconds(3)) { await operation() }
    }

    func finish(_ result: Result<Void, any Error>) {
        let continuation = state.withLock { state in
            guard state.result == nil else { return nil as CheckedContinuation<Void, any Error>? }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    func value() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result: Result<Void, any Error>? = state.withLock { state in
                    if let result = state.result { return result }
                    state.continuation = continuation
                    return nil as Result<Void, any Error>?
                }
                if let result { continuation.resume(with: result) }
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    static func perform(timeout: Duration, operation: @escaping @Sendable () async throws -> Void) async throws {
        let wait = RootWait()
        let worker = Task.detached {
            do {
                try await operation()
                wait.finish(.success(()))
            } catch {
                wait.finish(.failure(error))
            }
        }
        let timer = Task.detached {
            do {
                try await Task.sleep(for: timeout)
                wait.finish(.failure(RootHelperClient.Failure.timedOut))
            } catch {}
        }
        defer {
            worker.cancel()
            timer.cancel()
        }
        try await wait.value()
        try Task.checkCancellation()
    }
}
