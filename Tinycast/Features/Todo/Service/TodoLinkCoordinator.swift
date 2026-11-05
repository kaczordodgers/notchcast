import Foundation
import OSLog

@MainActor
final class TodoLinkCoordinator {
    typealias Exchange = @MainActor (TodoLinkPacket) async throws -> TodoLinkPacket

    private(set) var isRunning = false
    private(set) var isExchanging = false
    var canSync: Bool { isRunning && enabled() && store != nil }
    private weak var store: TodoStore?
    private let exchange: Exchange
    private let enabled: () -> Bool
    private let debounceDelay: Duration
    private var debounce: Task<Void, Never>?
    private var flight: Task<Void, Never>?
    private var flightID: UUID?
    private var generation = UUID()
    private var pending = false
    private var acknowledged = TodoVectorClock()

    init(debounceDelay: Duration = .seconds(2), enabled: @escaping () -> Bool = { true },
         exchange: @escaping Exchange) {
        self.debounceDelay = debounceDelay
        self.enabled = enabled
        self.exchange = exchange
    }

    deinit {
        debounce?.cancel()
        flight?.cancel()
    }

    func opened(_ store: TodoStore) {
        closed()
        self.store = store
        store.localCommit = { [weak self] in self?.committed() }
        if isRunning { requestExchange() }
    }

    func closed() {
        store?.localCommit = nil
        store = nil
        cancel()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        requestExchange()
    }

    func stop() {
        isRunning = false
        cancel()
    }

    func requestExchange() {
        guard isRunning, enabled(), store != nil else { return }
        pending = true
        debounce?.cancel()
        debounce = nil
        launch()
    }

    func respond(_ request: TodoLinkPacket) throws -> TodoLinkPacket {
        try Task.checkCancellation()
        guard isRunning, enabled(), let store else { throw TodoLinkPacket.Failure.unavailable }
        try store.receive(request.envelopes)
        return try TodoLinkPacket.make(from: store.replication, after: request.clock)
    }

    private func committed() {
        guard isRunning, enabled() else { return }
        debounce?.cancel()
        let delay = debounceDelay
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.debounce = nil
            self.requestExchange()
        }
    }

    private func cancel() {
        generation = UUID()
        acknowledged = TodoVectorClock()
        pending = false
        debounce?.cancel()
        debounce = nil
        flight?.cancel()
    }

    private func launch() {
        guard pending, flight == nil, isRunning, enabled(), store != nil else { return }
        pending = false
        let id = UUID()
        flightID = id
        let generation = generation
        let exchange = exchange
        isExchanging = true
        flight = Task { [weak self] in
            defer { self?.finished(id) }
            do {
                var peerClock = self?.acknowledged ?? TodoVectorClock()
                var more = true
                while more {
                    try Task.checkCancellation()
                    guard let packet = try self?.packet(after: peerClock, generation: generation) else { return }
                    let response = try await exchange(packet)
                    try Task.checkCancellation()
                    more = try self?.apply(response, generation: generation) ?? false
                    if more, response.clock == peerClock,
                       self?.store?.replication.vectorClock == packet.clock {
                        throw TodoLinkPacket.Failure.noProgress
                    }
                    peerClock = response.clock
                }
            } catch is CancellationError {
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast", category: "TodoSync")
                    .error("Task exchange failed: \(error)")
            }
        }
    }

    private func packet(after clock: TodoVectorClock, generation: UUID) throws -> TodoLinkPacket {
        guard self.generation == generation, isRunning, enabled(), let store else {
            throw TodoLinkPacket.Failure.unavailable
        }
        return try TodoLinkPacket.make(from: store.replication, after: clock)
    }

    private func apply(_ response: TodoLinkPacket, generation: UUID) throws -> Bool {
        guard self.generation == generation, isRunning, enabled(), let store else {
            throw TodoLinkPacket.Failure.unavailable
        }
        try store.receive(response.envelopes)
        acknowledged = response.clock
        return response.hasMore || !store.replication.envelopes(after: response.clock).isEmpty
    }

    private func finished(_ id: UUID) {
        guard flightID == id else { return }
        flight = nil
        flightID = nil
        isExchanging = false
        launch()
    }
}
