import Foundation
import Observation

@MainActor
@Observable
final class OpenBotAgentsModule {
    private(set) var agents: [OpenBotAgent] = []
    private(set) var pending: [String: OpenBotPending] = [:]
    private(set) var pendingFailures: [String: OpenBotFailure] = [:]
    private(set) var failure: OpenBotFailure?
    private let service: OpenBotService
    private let report: @MainActor (Int?, OpenBotFailure?) -> Void
    private let pollInterval: Duration
    private let availabilityChanged: () -> Void
    private var enabled = false
    private var active = false
    private var operation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: OpenBotService = .init(), pollInterval: Duration = .seconds(30),
         availabilityChanged: @escaping () -> Void = {},
         report: @escaping @MainActor (Int?, OpenBotFailure?) -> Void = { _, _ in }) {
        self.availabilityChanged = availabilityChanged
        self.pollInterval = pollInterval
        self.service = service
        self.report = report
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        availabilityChanged()
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
        pendingFailures = [:]
        failure = nil
        availabilityChanged()
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
        let service = service, pollInterval = pollInterval
        task = Task { [weak self] in
            var reportResult = reportResult
            repeat {
                do {
                    let agents = try await service.agents()
                    var pending: [String: OpenBotPending] = [:]
                    var pendingFailures: [String: OpenBotFailure] = [:]
                    for agent in agents {
                        do {
                            pending[agent.id] = try await service.pending(agent: agent.id)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            try Task.checkCancellation()
                            pendingFailures[agent.id] = (error as? OpenBotFailure) ?? .unreachable
                        }
                    }
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.agents = agents
                    self.pending = pending
                    self.pendingFailures = pendingFailures
                    self.failure = nil
                    if reportResult { self.report(pending.values.filter(\.isWaiting).count, nil) }
                } catch {
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.agents = []
                    self.pending = [:]
                    self.pendingFailures = [:]
                    self.failure = (error as? OpenBotFailure) ?? .unreachable
                    if reportResult { self.report(nil, self.failure) }
                }
                reportResult = false
                guard let self, self.active else { return }
                do { try await Task.sleep(for: pollInterval) } catch { return }
            } while !Task.isCancelled
        }
    }

    func waitUntilIdle() async { await task?.value }
}
