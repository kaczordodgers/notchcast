import Foundation
import Observation

@MainActor
@Observable
final class AgentSessionsModule: NotchcastModule {
    private(set) var snapshot = AgentSessionIndex.Snapshot()
    @ObservationIgnored private var index = AgentSessionIndex()
    @ObservationIgnored private var task: Task<Void, Never>?
    private let roots: [AgentSessionIndex.Root]
    private var enabled = false
    private var demanded = false
    private var operation = UUID()

    init(roots: [AgentSessionIndex.Root] = AgentSessionIndex.Root.defaults(
        home: FileManager.default.homeDirectoryForCurrentUser)) {
        self.roots = roots
    }

    func start() {
        enabled = true
        if demanded { refresh() }
    }

    func stop() {
        enabled = false
        cancel()
        snapshot = .init()
        index = .init()
    }

    func setDemand(_ demanded: Bool) {
        guard self.demanded != demanded else { return }
        self.demanded = demanded
        if demanded { refresh() } else { cancel() }
    }

    func refresh() {
        guard enabled else { return }
        cancel()
        let identity = operation
        let roots = roots
        let initial = index
        task = Task { [weak self] in
            var current = initial
            repeat {
                do {
                    let (updated, snapshot) = try await Self.scan(current, roots: roots)
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.index = updated
                    self.snapshot = snapshot
                    current = updated
                    guard self.demanded else { self.task = nil; return }
                } catch {
                    return
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private func cancel() {
        operation = UUID()
        task?.cancel()
        task = nil
    }

    @concurrent
    private static func scan(_ index: AgentSessionIndex, roots: [AgentSessionIndex.Root]) async throws
        -> (AgentSessionIndex, AgentSessionIndex.Snapshot) {
        var updated = index
        let snapshot = try updated.refresh(roots: roots)
        return (updated, snapshot)
    }
}
