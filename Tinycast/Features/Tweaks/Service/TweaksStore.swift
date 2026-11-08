import Foundation
import Observation

@MainActor
@Observable
final class TweaksStore {
    private(set) var enabled = false
    private(set) var busy = false
    private(set) var plans: [String: TypingPreferencePlan]
    @ObservationIgnored private let read: (TypingPreferencePlan.Preference) throws -> TypingPreferencePlan.Value?
    @ObservationIgnored private let run: ([TypingPreferencePlan.Command]) async throws -> Void
    @ObservationIgnored private let save: ([String: TypingPreferencePlan]) throws -> Void

    init(plans: [String: TypingPreferencePlan] = [:],
         read: @escaping (TypingPreferencePlan.Preference) throws -> TypingPreferencePlan.Value?,
         run: @escaping ([TypingPreferencePlan.Command]) async throws -> Void,
         save: @escaping ([String: TypingPreferencePlan]) throws -> Void) {
        self.plans = plans.compactMapValues { plan in
            let entries = plan.entries.filter {
                $0.write.preference.domain != "com.apple.dock" || $0.write.preference.key != "mru-spaces"
            }
            if entries.isEmpty, !plan.entries.isEmpty,
               (plan.extraApply ?? []).isEmpty, (plan.extraRevert ?? []).isEmpty { return nil }
            return TypingPreferencePlan(entries: entries, extraApply: plan.extraApply, extraRevert: plan.extraRevert)
        }
        self.read = read
        self.run = run
        self.save = save
    }

    func start() { enabled = true }
    func suspend() { enabled = false }

    func apply(_ identifier: String, plan: () throws -> TypingPreferencePlan) async throws {
        guard enabled, !busy, plans[identifier] == nil else { return }
        busy = true
        defer { busy = false }
        let plan = try plan()
        plans[identifier] = plan
        try save(plans)
        try await run(plan.apply)
        if !enabled { try await revert() }
    }

    func set(_ identifier: String, writes: [TypingPreferencePlan.Write], on: Bool) async throws {
        guard enabled, !busy else { return }
        busy = true
        defer { busy = false }
        if on {
            let captured = try TypingPreferenceService().read(writes, using: read)
            let plan = TypingPreferencePlan(entries: captured.entries.map { entry in
                let original = plans[identifier]?.entries.first {
                    $0.write.preference == entry.write.preference
                }
                return .init(write: entry.write, previous: original.map { $0.previous } ?? entry.previous)
            })
            plans[identifier] = plan
            try save(plans)
            try await run(plan.apply)
        } else if let plan = plans[identifier] {
            try await restore(plan)
            plans.removeValue(forKey: identifier)
            try save(plans)
        }
        if !enabled { try await revert() }
    }

    func stop() async throws {
        enabled = false
        guard !busy else { return }
        busy = true
        defer { busy = false }
        try await revert()
    }

    private func revert() async throws {
        for identifier in plans.keys.sorted() {
            guard let plan = plans[identifier] else { continue }
            try await restore(plan)
            plans.removeValue(forKey: identifier)
            try save(plans)
        }
    }

    private func restore(_ plan: TypingPreferencePlan) async throws {
        var commands = plan.extraRevert ?? []
        for entry in plan.entries.reversed() {
            if entry.previous == nil, try read(entry.write.preference) == nil { continue }
            commands += TypingPreferencePlan(entries: [entry]).revert
        }
        try await run(commands)
    }
}
