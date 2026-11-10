// notchcast-kit: core platform
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/*.swift Tinycast/Features/Tweaks/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemTools/Model/*.swift Tinycast/Features/SystemTools/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemTools/UI/SystemToolsProcessRunner.swift
import Foundation

@main
struct TweaksStoreTests {
    @MainActor
    static func main() async throws {
        let suite = "test.tweaks." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(NotchcastFeature.allCases.filter(\.isSystemTweak).allSatisfy { !preferences.isOn($0) })
        var recorded: [TypingPreferencePlan.Command] = []
        var journal: [String: TypingPreferencePlan] = [:]
        let store = TweaksStore(read: { _ in .bool(true) }, run: { recorded += $0 }, save: { journal = $0 })
        let writes = TypingCatalog.writes["smart-punctuation"]!
        try await store.set("typing", writes: writes, on: true)
        precondition(recorded.isEmpty, "Disabled verbs must do nothing")
        store.start()
        try await store.set("typing", writes: writes, on: true)
        precondition(recorded.count == 2 && journal.count == 1)
        try await store.stop()
        precondition(recorded.count == 4 && journal.isEmpty)
        precondition(recorded.suffix(2).allSatisfy { $0.arguments.suffix(2) == ["-bool", "true"] })
        try await store.set("typing", writes: writes, on: false)
        precondition(recorded.count == 4)
        var current: TypingPreferencePlan.Value?
        let absent = TweaksStore(read: { _ in current }, run: { recorded += $0 }, save: { _ in })
        absent.start()
        try await absent.set("rate", writes: [.init("KeyRepeat", .integer(2))], on: true)
        current = .integer(2)
        try await absent.set("rate", writes: [.init("KeyRepeat", .integer(6))], on: true)
        try await absent.stop()
        precondition(recorded.last?.arguments == ["delete", ".GlobalPreferences", "KeyRepeat"])
        let library = TypingPreferencePlan(entries: [],
            extraApply: [FinderCatalog.library(home: URL(filePath: "/fixture"), hidden: false)],
            extraRevert: [FinderCatalog.library(home: URL(filePath: "/fixture"), hidden: true)])
        let decoded = try JSONDecoder().decode(TypingPreferencePlan.self, from: JSONEncoder().encode(library))
        precondition(decoded == library)
        precondition(library.permitsJournal(home: "/fixture"))
        precondition(!TypingPreferencePlan(entries: [], extraRevert: [
            .init(executable: "/usr/bin/open", arguments: ["/fixture/Evil.app"])
        ]).permitsJournal(home: "/fixture"))
        var reverted: [TypingPreferencePlan.Command] = []
        let missing = TweaksStore(plans: ["absent": .init(entries: [
            .init(write: .init("KeyRepeat", .integer(2)), previous: nil)
        ])], read: { _ in nil }, run: { reverted += $0 }, save: { _ in })
        try await missing.stop()
        precondition(reverted.isEmpty && missing.plans.isEmpty)
        let catalogWrites = Array(FinderCatalog.writes.values) + Array(TypingCatalog.writes.values)
        let emitted = catalogWrites.flatMap { writes in
            let plan = TypingPreferencePlan(entries: writes.map { .init(write: $0, previous: nil) },
                extraApply: [FinderCatalog.library(home: URL(filePath: "/fixture"), hidden: true)],
                extraRevert: [FinderCatalog.library(home: URL(filePath: "/fixture"), hidden: false)])
            return plan.apply + plan.revert
        }
        precondition(Set(emitted.map(\.executable)).isSubset(of: SystemToolsProcessRunner.allowedExecutables),
                     "The runner refuses a tool a catalog emits")
        precondition(SystemToolsProcessRunner.allowedExecutables.contains("/usr/bin/killall"))
        do {
            _ = try SystemToolsProcessRunner().run("/untrusted/journal", arguments: [])
            preconditionFailure("Untrusted executable accepted")
        } catch SystemToolsProcessRunner.Failure.invalidExecutable {}
        let timeout = TweaksStore(read: { _ in nil }, run: { _ in
            throw SystemToolsProcessRunner.Failure.timedOut
        }, save: { _ in })
        timeout.start()
        do {
            try await timeout.set("timeout", writes: writes, on: true)
            preconditionFailure("Expected timeout")
        } catch SystemToolsProcessRunner.Failure.timedOut {}
        precondition(!timeout.busy)
        print("8 passed, 0 failed")
    }
}
