import Foundation
import OSLog
import CryptoKit

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
    private var assembly = TodoLinkAssembly()
    private var peerReceipt: TodoLinkPacket.Receipt?
    var showFailure: (String) -> Void = { _ in }
    private var reported: Set<String> = []
    var pairingIdentity: () -> UUID? = { nil }
    private var pairingID: UUID?

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
        checkPairing()
        try Task.checkCancellation()
        guard isRunning, enabled(), let store else { throw TodoLinkPacket.Failure.unavailable }
        do {
            try receive(request, store: store)
            var response = try TodoLinkPacket.make(from: store.replication, after: request.clock, receipt: request.receipt)
            response.receipt = assembly.receipt
            reported.removeAll()
            return response
        } catch {
            report(error)
            throw error
        }
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
        assembly = TodoLinkAssembly()
        peerReceipt = nil
        reported.removeAll()
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
                       self?.store?.replication.vectorClock == packet.clock,
                       response.receipt == packet.receipt, response.chunk == nil, packet.chunk == nil {
                        throw TodoLinkPacket.Failure.noProgress
                    }
                    peerClock = response.clock
                }
                self?.reported.removeAll()
            } catch is CancellationError {
            } catch {
                guard self?.generation == generation else { return }
                self?.report(error)
                Logger(subsystem: NotchcastIdentity.releaseFallbackSubsystem, category: "TodoSync")
                    .error("Task exchange failed: \(error)")
            }
        }
    }

    private func packet(after clock: TodoVectorClock, generation: UUID) throws -> TodoLinkPacket {
        checkPairing()
        guard self.generation == generation, isRunning, enabled(), let store else {
            throw TodoLinkPacket.Failure.unavailable
        }
        var packet = try TodoLinkPacket.make(from: store.replication, after: clock, receipt: peerReceipt)
        packet.receipt = assembly.receipt
        return packet
    }

    private func apply(_ response: TodoLinkPacket, generation: UUID) throws -> Bool {
        guard self.generation == generation, isRunning, enabled(), let store else {
            throw TodoLinkPacket.Failure.unavailable
        }
        try receive(response, store: store)
        peerReceipt = response.receipt
        acknowledged = response.clock
        return response.hasMore || !store.replication.envelopes(after: response.clock).isEmpty
    }

    private func receive(_ packet: TodoLinkPacket, store: TodoStore) throws {
        var envelopes = packet.envelopes
        if let chunk = packet.chunk {
            if let existing = store.replication.envelopes.first(where: { $0.id == chunk.id }) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let bytes = try encoder.encode(existing)
                guard bytes.count == chunk.total, Data(SHA256.hash(data: bytes)) == chunk.digest else {
                    throw TodoReplicationError.conflictingEnvelope(replicaID: chunk.id.replicaID,
                                                                   sequence: chunk.id.sequence)
                }
            } else if let envelope = try assembly.receive(chunk) { envelopes.append(envelope) }
        }
        try store.receive(envelopes)
        if let chunk = packet.chunk, assembly.receipt == nil,
           !store.replication.envelopes.contains(where: { $0.id == chunk.id }) {
            throw TodoLinkPacket.Failure.noProgress
        }
    }

    private func checkPairing() {
        let identity = pairingIdentity()
        guard identity != pairingID else { return }
        pairingID = identity
        assembly = TodoLinkAssembly()
        peerReceipt = nil
        acknowledged = TodoVectorClock()
        reported.removeAll()
    }

    private func report(_ error: Error) {
        let kind: String
        let message: String
        switch error {
        case TodoReplicationError.conflictingEnvelope:
            kind = "conflict"
            message = String(localized: "Task sync found conflicting changes; the Macs may share a replica ID.", table: "Notchcast")
        case TodoLinkPacket.Failure.tooLarge:
            kind = "size"
            message = String(localized: "Task sync exceeded the 8 MB transfer limit.", table: "Notchcast")
        case is TodoReplicationError:
            kind = "rejected"
            message = String(localized: "Task sync failed; check Mac Link and try again.", table: "Notchcast")
        default:
            kind = String(reflecting: error)
            message = String(localized: "Task sync failed; check Mac Link and try again.", table: "Notchcast")
        }
        if reported.insert(kind).inserted { showFailure(message) }
    }

    private func finished(_ id: UUID) {
        guard flightID == id else { return }
        flight = nil
        flightID = nil
        isExchanging = false
        launch()
    }
}
