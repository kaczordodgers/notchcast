import Foundation
import Synchronization

/// One extraction at a time for every caller: they share journals and the recovery list.
nonisolated enum ArchiveExtractionGate {
    private struct State {
        var busy = false
        var waiters: [(id: UUID, turn: CheckedContinuation<Void, any Error>)] = []
    }

    private static let state = Mutex(State())

    static func enter() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { turn in
                let settled: Result<Void, any Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if !state.busy {
                        state.busy = true
                        return .success(())
                    }
                    state.waiters.append((id, turn))
                    return nil
                }
                if let settled { turn.resume(with: settled) }
            }
        } onCancel: {
            let turn = state.withLock { state in
                state.waiters.firstIndex { $0.id == id }.map { state.waiters.remove(at: $0).turn }
            }
            turn?.resume(throwing: CancellationError())
        }
    }

    static func leave() {
        let next: CheckedContinuation<Void, any Error>? = state.withLock { state in
            if state.waiters.isEmpty {
                state.busy = false
                return nil
            }
            return state.waiters.removeFirst().turn
        }
        next?.resume()
    }
}
