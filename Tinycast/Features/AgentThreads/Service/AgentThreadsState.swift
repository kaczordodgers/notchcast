import Foundation
import Observation

@MainActor
@Observable
final class AgentThreadsState {
    enum Status: Equatable { case idle, loading, ready, unavailable, failed }
    private(set) var threads: [AgentThread] = []
    private(set) var status = Status.idle
    private let runner: any AgentThreadRunning
    private let now: @Sendable () -> Date
    private var enabled = false
    private var active = false
    private var operation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(runner: any AgentThreadRunning = AgentThreadRunner(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.now = now
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        refresh()
    }

    func stop() {
        enabled = false
        cancel()
        threads = []
        status = .idle
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active { refresh() } else { cancel() }
    }

    func refresh() {
        guard enabled else { return }
        cancel()
        let identity = operation
        status = .loading
        task = Task { [weak self, runner, now] in
            repeat {
                do {
                    let data = try await runner.run(arguments: ["thread", "list", "--json"])
                    var rows = try AgentThreadParser.list(data)
                    for index in rows.indices where !rows[index].settled {
                        try Task.checkCancellation()
                        let detail = try await runner.run(arguments: ["thread", "show", rows[index].id, "--json"])
                        rows[index] = try AgentThreadParser.show(detail, updating: rows[index])
                    }
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.threads = AgentThreadParser.select(rows, now: now())
                    self.status = .ready
                } catch {
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.status = (error as? AgentThreadFailure) == .unavailable ? .unavailable : .failed
                }
                guard self?.active == true else { return }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            } while !Task.isCancelled
        }
    }

    func waitUntilIdle() async { await task?.value }

    private func cancel() {
        operation = UUID()
        task?.cancel()
        task = nil
    }
}
