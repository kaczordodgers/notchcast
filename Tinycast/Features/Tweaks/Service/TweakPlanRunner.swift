import Foundation

nonisolated struct TweakPlanRunner {
    struct Receipt: Sendable {
        let completed: [MacSetupPlan.Change]
        let failure: (any Error)?
    }

    func apply(_ plan: MacSetupPlan,
               write: (TweakPreference, TweakValue) throws -> Void) -> Receipt {
        var completed: [MacSetupPlan.Change] = []
        for change in plan.changes {
            do {
                try write(change.preference, change.after)
                completed.append(change)
            } catch {
                return Receipt(completed: completed, failure: error)
            }
        }
        return Receipt(completed: completed, failure: nil)
    }
}
