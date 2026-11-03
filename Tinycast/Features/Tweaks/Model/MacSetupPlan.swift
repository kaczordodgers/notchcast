import Foundation

nonisolated struct MacSetupPlan: Equatable, Sendable {
    struct Change: Equatable, Sendable {
        let preference: TweakPreference
        let before: TweakValue
        let after: TweakValue
    }

    enum Failure: Error { case missingReading, duplicatePreference, drift }

    let changes: [Change]

    init(desired: [(TweakPreference, TweakValue)], readings: [TweakPreference: TweakValue]) throws {
        var seen = Set<TweakPreference>()
        changes = try desired.compactMap { preference, value in
            guard seen.insert(preference).inserted else { throw Failure.duplicatePreference }
            guard let before = readings[preference] else { throw Failure.missingReading }
            return before == value ? nil : Change(preference: preference, before: before, after: value)
        }
    }

    func undo(readings: [TweakPreference: TweakValue]) throws -> MacSetupPlan {
        guard changes.allSatisfy({ readings[$0.preference] == $0.after }) else { throw Failure.drift }
        return try MacSetupPlan(desired: changes.reversed().map { ($0.preference, $0.before) }, readings: readings)
    }
}
