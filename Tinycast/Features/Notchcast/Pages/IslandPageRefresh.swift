import Foundation
import Observation

@MainActor @Observable
final class IslandPageRefresh {
    private(set) var isRefreshing = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var identity: UUID?

    func run(_ operation: @escaping @MainActor () async -> Void) {
        cancel()
        let identity = UUID()
        self.identity = identity
        isRefreshing = true
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await operation()
            guard !Task.isCancelled, let self, self.identity == identity else { return }
            isRefreshing = false
            task = nil
            self.identity = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        identity = nil
        isRefreshing = false
    }
}
