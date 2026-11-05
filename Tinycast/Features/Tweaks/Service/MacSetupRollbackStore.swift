import Foundation

nonisolated struct MacSetupRollbackStore: Sendable {
    enum Failure: Error, LocalizedError {
        case corruptJournal
        var errorDescription: String? {
            String(localized: "The setup rollback journal was corrupt and has been set aside. Retry to start a new journal.",
                   table: "Notchcast")
        }
    }
    let url: URL

    func read() throws -> [MacSetupPlan.Change] {
        guard FileManager().fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode([MacSetupPlan.Change].self, from: data)
        } catch is DecodingError {
            let destination = url.appendingPathExtension(UUID().uuidString + ".corrupt")
            try FileManager().moveItem(at: url, to: destination)
            throw Failure.corruptJournal
        }
    }

    func save(_ changes: [MacSetupPlan.Change]) throws {
        try FileManager().createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(changes).write(to: url, options: .atomic)
    }

    func apply(_ plan: MacSetupPlan, read: (TweakPreference) throws -> TweakValue,
               write: (TweakPreference, TweakValue) throws -> Void) -> TweakPlanRunner.Receipt {
        var completed: [MacSetupPlan.Change] = []
        do {
            var journal = try self.read()
            for change in plan.changes {
                guard try read(change.preference) == change.before else { throw MacSetupPlan.Failure.drift }
                if let index = journal.firstIndex(where: { $0.preference == change.preference }) {
                    guard journal[index].after == change.before else { throw MacSetupPlan.Failure.drift }
                    journal[index] = .init(preference: change.preference,
                        before: journal[index].before, after: change.after)
                } else {
                    journal.append(change)
                }
                try save(journal)
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
