import Foundation

nonisolated struct TweakPlanSession {
    private(set) var completed: [MacSetupPlan.Change] = []

    mutating func apply(_ plan: MacSetupPlan,
                        write: (TweakPreference, TweakValue) throws -> Void) throws {
        guard completed.isEmpty else { throw MacSetupPlan.Failure.drift }
        let receipt = TweakPlanRunner().apply(plan, write: write)
        completed = receipt.completed
        if let failure = receipt.failure { throw failure }
    }

    mutating func undo(readings: [TweakPreference: TweakValue],
                       write: (TweakPreference, TweakValue) throws -> Void) throws {
        guard completed.allSatisfy({ readings[$0.preference] == $0.after }) else {
            throw MacSetupPlan.Failure.drift
        }
        while let change = completed.last {
            try write(change.preference, change.before)
            completed.removeLast()
        }
    }
}
