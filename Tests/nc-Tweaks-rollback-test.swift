import Foundation

@main
struct MacSetupRollbackTests {
    static func main() throws {
        enum Failure: Error { case refused }
        let folder = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager().removeItem(at: folder) }
        let url = folder.appendingPathComponent("rollback.json")
        let first = TweakPreference(domain: "test", key: "first")
        let second = TweakPreference(domain: "test", key: "second")
        let original: [TweakPreference: TweakValue] = [first: .absent, second: .bool(false)]
        var values = original
        let plan = try MacSetupPlan(desired: [(first, .integer(2)), (second, .bool(true))], readings: values)
        let store = MacSetupRollbackStore(url: url)
        let receipt = store.apply(plan, read: { values[$0]! }) { preference, value in
            let journal = try store.read()
            precondition(journal.last?.preference == preference)
            values[preference] = value
        }
        precondition(receipt.failure == nil && receipt.completed.count == 2)
        let later = try MacSetupPlan(desired: [(first, .integer(3))], readings: values)
        let repeated = store.apply(later, read: { values[$0]! }) { values[$0] = $1 }
        precondition(repeated.failure == nil && values[first] == .integer(3))
        let earliest = try store.read()
        precondition(earliest.first?.before == .absent)
        try MacSetupRollbackStore(url: url).rollback(read: { values[$0]! }) { values[$0] = $1 }
        let cleared = try store.read()
        precondition(values == original && cleared.isEmpty)
        let partial = store.apply(plan, read: { values[$0]! }) { preference, value in
            if preference == second { throw Failure.refused }
            values[preference] = value
        }
        precondition(partial.failure != nil && partial.completed.count == 1)
        var restored: [TweakPreference] = []
        try MacSetupRollbackStore(url: url).rollback(read: { values[$0]! }) {
            restored.append($0)
            values[$0] = $1
        }
        precondition(restored == [first] && values == original)
        _ = store.apply(plan, read: { values[$0]! }) { values[$0] = $1 }
        values[second] = .string("external change")
        do {
            try store.rollback(read: { values[$0]! }) { _, _ in fatalError("Drift must refuse writes") }
            fatalError("Expected drift")
        } catch MacSetupPlan.Failure.drift {}
        let retained = try store.read()
        precondition(retained.count == 2)
        for rollback in [false, true] {
            try Data("broken".utf8).write(to: url)
            if rollback {
                do {
                    try store.rollback(read: { values[$0]! }) { _, _ in fatalError() }
                    fatalError()
                } catch MacSetupRollbackStore.Failure.corruptJournal {}
            } else {
                let failed = store.apply(plan, read: { values[$0]! }) { _, _ in fatalError() }
                precondition(failed.failure is MacSetupRollbackStore.Failure)
            }
            let empty = try store.read()
            precondition(empty.isEmpty)
            values = original
            let retry = store.apply(plan, read: { values[$0]! }) { values[$0] = $1 }
            precondition(retry.failure == nil)
            try store.rollback(read: { values[$0]! }) { values[$0] = $1 }
            precondition(values == original)
        }
        let quarantined = try FileManager().contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".corrupt") }
        precondition(quarantined.count == 2)
        print("PASS: corrupt apply/rollback journal quarantined once; retry and rollback succeed")
        print("PASS: journal precedes writes; relaunch restores all; partial failure restores applied only; drift refused")
    }
}
