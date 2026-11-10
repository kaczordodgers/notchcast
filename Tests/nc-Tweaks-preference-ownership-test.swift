import Foundation

@main
struct PreferenceOwnershipTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { failures.append(message) }
        }
        expect(DockCatalog.writes.values.flatMap { $0 }.allSatisfy {
            $0.preference.domain != "com.apple.dock" || $0.preference.key != "mru-spaces"
        }, "Dock tweaks must not write the SpacesOrder preference")
        let expectedDelay = ["write", "com.apple.dock", "autohide-delay", "-float", "0.0"]
        let dock = TypingPreferencePlan(entries: DockCatalog.writes["dock-delay"]!.map {
            .init(write: $0, previous: nil)
        })
        expect(dock.apply.first?.arguments == expectedDelay, "Dock delay is a real value")
        let typing = TypingPreferencePlan(entries: [.init(write: .init("KeyRepeat", .integer(2)), previous: nil)])
        let legacy = TypingPreferencePlan(entries: [.init(
            write: .init("com.apple.dock", "mru-spaces", .bool(false)), previous: .bool(true))])
        var recorded: [TypingPreferencePlan.Command] = []
        let mixed = TypingPreferencePlan(entries: legacy.entries + typing.entries)
        let store = TweaksStore(plans: ["renamed": legacy, "mixed": mixed, "spaces-fixed": typing],
                               read: { _ in .integer(2) }, run: { recorded += $0 }, save: { _ in })
        expect(store.plans["renamed"] == nil, "Retired preference is ignored regardless of plan identifier")
        expect(store.plans["mixed"] == typing, "Mixed journals retain unrelated preferences")
        expect(store.plans["spaces-fixed"] == typing, "Plan identifier alone does not discard unrelated preferences")
        try await store.stop()
        expect(!recorded.contains { $0.arguments.contains("mru-spaces") },
               "Old tweak journal must not restore SpacesOrder's preference")
        expect(recorded.contains { $0.arguments.contains("KeyRepeat") }, "Unrelated journals still restore")
        for failure in failures { print("FAIL: \(failure)") }
        print("Preference ownership: \(checks - failures.count) passed, \(failures.count) failed")
        if !failures.isEmpty { exit(1) }
    }
}
