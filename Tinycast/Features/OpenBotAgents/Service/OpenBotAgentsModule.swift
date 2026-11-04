import Foundation
import Observation

@MainActor
@Observable
final class OpenBotAgentsModule {
    private(set) var agents: [OpenBotAgent] = []
    private(set) var pending: [String: OpenBotPending] = [:]
    private(set) var failure: OpenBotFailure?
    private let service: OpenBotService
    private let report: (Int?, OpenBotFailure?) -> Void
    private var enabled = false
    private var active = false
    private var operation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: OpenBotService = .init(), report: @escaping (Int?, OpenBotFailure?) -> Void = { _, _ in }) {
        self.service = service
        self.report = report
    }

    func start() {
        enabled = true
        refresh()
    }

    func stop() {
        enabled = false
        active = false
        operation = UUID()
        task?.cancel()
        task = nil
        agents = []
        pending = [:]
        failure = nil
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        refresh()
    }

    func refresh(reportResult: Bool = false) {
        guard enabled else { return }
        task?.cancel()
        operation = UUID()
        let identity = operation
        let service = service
        task = Task { [weak self] in
            repeat {
                do {
                    let agents = try await service.agents()
                    var pending: [String: OpenBotPending] = [:]
                    for agent in agents { pending[agent.id] = try await service.pending(agent: agent.id) }
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.agents = agents
                    self.pending = pending
                    self.failure = nil
                    if reportResult { self.report(pending.values.filter(\.isWaiting).count, nil) }
                } catch {
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.agents = []
                    self.pending = [:]
                    self.failure = (error as? OpenBotFailure) ?? .unreachable
                    if reportResult { self.report(nil, self.failure) }
                }
                guard let self, self.active else { return }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
    }

    func waitUntilIdle() async { await task?.value }
}
