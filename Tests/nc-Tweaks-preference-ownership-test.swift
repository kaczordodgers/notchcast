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
        let entries = MacSetupPresetCatalog.entries(home: URL(filePath: "/fixture"))
        expect(DockCatalog.writes.values.flatMap { $0 }.allSatisfy {
            $0.preference.domain != "com.apple.dock" || $0.preference.key != "mru-spaces"
        }, "Dock tweaks must not write the SpacesOrder preference")
        expect(!entries.contains { $0.id == "spaces-fixed" }, "Setup preset must not offer the removed Spaces tweak")
        for entry in entries {
            switch entry.action {
            case .preferences(let preferences), .forced(let preferences):
                expect(preferences.allSatisfy { $0.0.domain != "com.apple.dock" || $0.0.key != "mru-spaces" },
                       "Setup preset must leave SpacesOrder's preference alone")
            default: break
            }
        }
        let expectedDelay = ["write", "com.apple.dock", "autohide-delay", "-float", "0.0"]
        let dock = TypingPreferencePlan(entries: DockCatalog.writes["dock-delay"]!.map {
            .init(write: $0, previous: nil)
        })
        expect(dock.apply.first?.arguments == expectedDelay, "Dock delay is a real value")
        let setupDelay = MacSetupCatalog.preferences.first { $0.0.key == "autohide-delay" }!
        expect(TweakCommand.preference(setupDelay.0, value: setupDelay.1).arguments == expectedDelay,
               "Setup delay uses the same real value as Dock")
        for entry in entries where entry.id == "dock-delay" {
            if case .preferences(let preferences) = entry.action {
                expect(preferences.map { TweakCommand.preference($0.0, value: $0.1).arguments } == [expectedDelay],
                       "Setup preset delay uses the same real value as Dock")
            }
        }
        let global = TweakPreference(domain: ".GlobalPreferences", key: "KeyRepeat")
        let typing = TypingPreferencePlan(entries: [.init(write: .init("KeyRepeat", .integer(2)), previous: nil)])
        expect(TweakCommand.preference(global, value: .integer(2)).arguments == typing.apply[0].arguments,
               "Both models write the same global domain")
        expect(TweakCommand.preference(global, value: .absent).arguments == typing.revert[0].arguments,
               "Both models delete from the same global domain")
        expect(TweakCommand.preference(.init(domain: global.domain, key: global.key, currentHost: true),
                                       value: .integer(2)).arguments == ["-currentHost"] + typing.apply[0].arguments,
               "Current-host writes retain the canonical global domain")
        let encoded = try JSONEncoder().encode(setupDelay.1)
        expect(try JSONDecoder().decode(TweakValue.self, from: encoded) == setupDelay.1,
               "Delay value survives the rollback journal")
        let legacy = TypingPreferencePlan(entries: [.init(
            write: .init("com.apple.dock", "mru-spaces", .bool(false)), previous: .bool(true))])
        var recorded: [TypingPreferencePlan.Command] = []
        let store = TweaksStore(plans: ["spaces-fixed": legacy, "other": typing],
                               read: { _ in .integer(2) }, run: { recorded += $0 }, save: { _ in })
        try await store.stop()
        expect(!recorded.contains { $0.arguments.contains("mru-spaces") },
               "Old tweak journal must not restore SpacesOrder's preference")
        expect(recorded.contains { $0.arguments.contains("KeyRepeat") }, "Unrelated journals still restore")
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rollback = MacSetupRollbackStore(url: folder.appending(path: "rollback.json"))
        let oldSpaces = TweakPreference(domain: "com.apple.dock", key: "mru-spaces")
        try rollback.save([.init(preference: oldSpaces, before: .bool(true), after: .bool(false)),
                           .init(preference: global, before: .integer(6), after: .integer(2))])
        var restored: [TweakPreference] = []
        try rollback.rollback(read: { $0 == oldSpaces ? .bool(false) : .integer(2) },
                              write: { preference, _ in restored.append(preference) })
        expect(restored == [global], "Old setup journal ignores the removed preference and restores the rest")
        for failure in failures { print("FAIL: \(failure)") }
        print("Preference ownership: \(checks - failures.count) passed, \(failures.count) failed")
        if !failures.isEmpty { exit(1) }
    }
}
