import Foundation
import Observation

@MainActor @Observable
final class IslandPageRefresh {
    private(set) var isRefreshing = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var identity: UUID?
    /// A reload that ends at once would never draw the spinner, so ⌘R would seem to do nothing.
    private let minimumVisible: Duration

    init(minimumVisible: Duration = .zero) {
        self.minimumVisible = minimumVisible
    }

    func run(_ operation: @escaping @MainActor () async -> Void) {
        cancel()
        let identity = UUID()
        self.identity = identity
        isRefreshing = true
        let shownUntil = ContinuousClock.now + minimumVisible
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await operation()
            try? await Task.sleep(until: shownUntil, clock: .continuous)
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
