import Foundation

nonisolated struct MacSetupRollbackStore: Sendable {
    let url: URL

    func read() throws -> [MacSetupPlan.Change] {
        guard FileManager().fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([MacSetupPlan.Change].self, from: Data(contentsOf: url))
    }

    func save(_ changes: [MacSetupPlan.Change]) throws {
        try FileManager().createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(changes).write(to: url, options: .atomic)
    }

    func apply(_ plan: MacSetupPlan, read: (TweakPreference) throws -> TweakValue,
               write: (TweakPreference, TweakValue) throws -> Void) -> TweakPlanRunner.Receipt {
        var completed: [MacSetupPlan.Change] = []
        do {
            guard try self.read().isEmpty else { throw MacSetupPlan.Failure.drift }
            for change in plan.changes {
                guard try read(change.preference) == change.before else { throw MacSetupPlan.Failure.drift }
                try save(completed + [change])
                try write(change.preference, change.after)
                completed.append(change)
            }
            return .init(completed: completed, failure: nil)
        } catch {
            return .init(completed: completed, failure: error)
        }
    }

    func rollback(read: (TweakPreference) throws -> TweakValue,
                  write: (TweakPreference, TweakValue) throws -> Void) throws {
        var changes = try self.read()
        while let change = changes.last {
            let current = try read(change.preference)
            guard current == change.before || current == change.after else { throw MacSetupPlan.Failure.drift }
            if current != change.before { try write(change.preference, change.before) }
            changes.removeLast()
            try save(changes)
        }
    }
}
