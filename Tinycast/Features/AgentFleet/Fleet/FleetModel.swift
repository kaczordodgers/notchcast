import Foundation
import Observation

@MainActor
@Observable
final class FleetModel {
    struct Row: Identifiable {
        struct ID: Hashable { let machine: String; let thread: String }
        let id: ID
        let thread: FleetSnapshot.Thread
        let runLength: TimeInterval
        let childCount: Int?
        let venture: String?
        let weight: String?
        let childCap: Int?
    }

    struct Machine {
        let destination: FleetSnapshot.Destination
        let failure: FleetSnapshot.Failure?
        let report: FleetSnapshot.GuardReport?
        let limits: FleetSnapshot.Limits?

        var message: String? {
            switch failure {
            case .linkExpired: String(localized: "MBP link expired: relink in T3")
            case .unavailable: String(localized: "Fleet data unavailable.")
            case nil: nil
            }
        }
    }

    private(set) var rows: [Row] = []
    private(set) var machines: [Machine] = []
    private(set) var isRefreshing = false
    @ObservationIgnored private let source: any FleetThreadSource
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var generation = 0
    var destinations: [FleetSnapshot.Destination] {
        didSet { invalidate() }
    }

    init(source: any FleetThreadSource, destinations: [FleetSnapshot.Destination], clock: @escaping () -> Date) {
        self.source = source
        self.destinations = destinations
        self.clock = clock
    }

    func invalidate() {
        generation += 1
        isRefreshing = false
        rows = []
        machines = []
    }

    func refresh() async {
        generation += 1
        let operation = generation
        let destinations = destinations
        isRefreshing = true
        let source = source
        var results: [Result<FleetSnapshot, FleetSnapshot.Failure>] = []
        for destination in destinations {
            do {
                results.append(.success(try await source.read(destination)))
            } catch let failure as FleetSnapshot.Failure {
                results.append(.failure(failure))
            } catch {
                results.append(.failure(.unavailable))
            }
            guard !Task.isCancelled, operation == generation else {
                if operation == generation { isRefreshing = false }
                return
            }
        }
        guard operation == generation, destinations == self.destinations else { return }
        isRefreshing = false
        guard !Task.isCancelled else { return }
        let now = clock()
        var rows: [Row] = []
        machines = zip(destinations, results).map { destination, result in
            switch result {
            case .failure(let failure):
                return Machine(destination: destination, failure: failure, report: nil, limits: nil)
            case .success(let snapshot):
                rows += Self.rows(snapshot, destination: destination, now: now)
                return Machine(destination: destination, failure: nil, report: snapshot.report, limits: snapshot.limits)
            }
        }
        self.rows = rows.sorted {
            if $0.thread.state != $1.thread.state { return $0.thread.state.rawValue < $1.thread.state.rawValue }
            if $0.thread.began != $1.thread.began { return $0.thread.began > $1.thread.began }
            if $0.id.machine != $1.id.machine { return $0.id.machine < $1.id.machine }
            return $0.id.thread < $1.id.thread
        }
    }

    private static func rows(
        _ snapshot: FleetSnapshot, destination: FleetSnapshot.Destination, now: Date
    ) -> [Row] {
        snapshot.threads.compactMap { thread in
            guard !(thread.workspacePath ?? "").split(separator: "/").contains("agent-2784f2ac") else { return nil }
            if thread.state == .finished {
                guard let ended = thread.ended, ended <= now, now.timeIntervalSince(ended) <= 1_800 else { return nil }
            }
            let lead = snapshot.report?.leads.first { $0.id == thread.id }
            let cap = lead.flatMap { lead in
                lead.venture.flatMap { snapshot.limits?.ventureChildCaps?[$0] } ?? snapshot.limits?.childCap
            }
            return Row(
                id: .init(machine: destination.machine, thread: thread.id), thread: thread,
                runLength: max(0, (thread.ended ?? now).timeIntervalSince(thread.began)),
                childCount: lead?.children, venture: lead?.venture, weight: lead?.weight, childCap: cap)
        }
    }
}
