// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

@MainActor
final class AudioPriorityManager {
    private let transport: any AudioPriorityTransport
    private let store: any AudioPriorityStore
    private let report: (any Error) -> Void
    private var lifetime: UUID?
    private var pending: Task<Void, Never>?
    private var connected: [AudioPriorityDevice.Direction: Set<String>] = [:]
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
        do {
            try transport.start { [weak self] in
                Task { @MainActor [weak self] in self?.schedule(identity) }
            }
            refresh(apply: false)
        } catch {
            report(error)
            stop()
        }
    }

    func stop() {
        guard lifetime != nil else { return }
        lifetime = nil
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

    private func refresh(apply: Bool) {
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
                guard apply, let previous, previous != available else { continue }
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
