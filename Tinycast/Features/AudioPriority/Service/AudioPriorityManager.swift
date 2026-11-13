// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation
import Observation

@MainActor
final class AudioPriorityManager {
    private let transport: any AudioPriorityTransport
    private let store: any AudioPriorityStore
    private let report: (any Error) -> Void
    private var lifetime: UUID?
    private var pending: Task<Void, Never>?
    private var connected: [AudioPriorityDevice.Direction: Set<String>] = [:]
    private var listening = false
    var clearFailure: () -> Void = {}
    var inventoryChanged: ([AudioPriorityDevice]) -> Void = { _ in }
    var succeeded: () -> Void = {}

    init(transport: any AudioPriorityTransport, store: any AudioPriorityStore,
         report: @escaping (any Error) -> Void) {
        self.transport = transport
        self.store = store
        self.report = report
    }

    isolated deinit { stop() }

    func start() {
        guard lifetime == nil else { return }
        let identity = UUID()
        lifetime = identity
        clearFailure()
        refresh(apply: false)
        trackRankings(identity)
    }

    private func listen(_ identity: UUID) {
        guard !listening else { return }
        do {
            try transport.start { [weak self] in
                Task { @MainActor [weak self] in self?.schedule(identity) }
            }
            listening = true
        } catch {
            report(error)
        }
    }

    func stop() {
        clearFailure()
        guard lifetime != nil else { return }
        lifetime = nil
        listening = false
        pending?.cancel()
        pending = nil
        connected.removeAll()
        do { try transport.stop() } catch { report(error) }
    }

    private func schedule(_ identity: UUID) {
        guard lifetime == identity else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard let self, self.lifetime == identity, !Task.isCancelled else { return }
            self.pending = nil
            self.refresh(apply: true)
        }
    }

    func refresh() { refresh(apply: true, force: true) }

    private func trackRankings(_ identity: UUID) {
        withObservationTracking {
            for direction in AudioPriorityDevice.Direction.allCases { _ = store.ranking(for: direction) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.lifetime == identity else { return }
                self.refresh()
                self.trackRankings(identity)
            }
        }
    }

    private func refresh(apply: Bool, force: Bool = false) {
        guard let identity = lifetime else { return }
        clearFailure()
        listen(identity)
        do {
            let devices = try transport.devices()
            inventoryChanged(devices)
            for direction in AudioPriorityDevice.Direction.allCases {
                let uids = devices.filter { $0.direction == direction }.map(\.uid)
                let available = Set(uids)
                let previous = connected[direction]
                connected[direction] = available
                var ranking = store.ranking(for: direction)
                let before = ranking
                ranking.appendUnknown(uids)
                if ranking != before { store.save(ranking, for: direction) }
                guard apply, force || (previous != nil && previous != available) else { continue }
                do {
                    let current = try transport.defaultUID(for: direction)
                    if let target = AudioPriorityPolicy.target(
                        ranking: ranking, connected: available, current: current) {
                        try transport.setDefault(uid: target, for: direction)
                        succeeded()
                    }
                } catch { report(error) }
            }
        } catch { report(error) }
    }
}
