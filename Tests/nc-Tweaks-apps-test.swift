import Foundation

@main
struct TweaksAppsTests {
    static func main() throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            checks += 1
            if !value { fatalError(message) }
        }
        let service = TypingPreferenceService()
        _ = try service.readPreference(.init(domain: "com.apple.AMPDevicesClient",
                                             key: "AutomaticDeviceBackupsDisabled"))
        let punctuation = TypingCatalog.writes["smart-punctuation"]!
        let plan = try service.read(punctuation) { preference in
            preference.key.contains("Quote") ? .bool(true) : nil
        }
        expect(plan.apply.count == 2, "Punctuation changes both preferences")
        expect(plan.revert.first?.arguments.first == "delete", "Absent key restored as absent")
        expect(plan.revert.last?.arguments.suffix(2) == ["-bool", "true"], "Original value restored")
        expect(try JSONDecoder().decode(TypingPreferencePlan.self, from: JSONEncoder().encode(plan)) == plan,
               "Journal survives persistence")
        var recorded: [TypingPreferencePlan.Command] = []
        try service.run(plan.apply) { recorded.append($0) }
        expect(recorded == plan.apply, "Runner injection preserves order")
        enum Failure: Error { case refused }
        var count = 0
        do {
            try service.run(plan.apply) { _ in count += 1; throw Failure.refused }
            fatalError("Runner failure swallowed")
        } catch Failure.refused { expect(count == 1, "Stop on first failed command") }
        do {
            _ = try service.read(punctuation + punctuation) { _ in nil }
            fatalError("Duplicate writes accepted")
        } catch TypingPreferenceService.Failure.duplicatePreference { checks += 1 }
        do {
            _ = try service.read(punctuation) { _ in throw Failure.refused }
            fatalError("Unreadable key treated as absent")
        } catch Failure.refused { checks += 1 }
        expect(TypingCatalog.writes.count == 7, "Five typing toggles and two repeat settings")
        expect(!TypingCatalog.preset.contains("autocorrect"), "Preset preserves autocorrect")
        expect(FinderCatalog.writes.count == 15, "Twelve preference toggles and three additional settings")
        let home = URL(fileURLWithPath: "/tmp/home with spaces")
        expect(FinderCatalog.library(home: home, hidden: false).arguments ==
               ["nohidden", "/tmp/home with spaces/Library"], "Library path stays one argument")
        expect(FinderCatalog.downloads(home: home).count == 2, "Downloads sets both Finder keys")
        expect(!FinderCatalog.preset.contains("hidden-files"), "Hidden-files preset stays off")
        let all = TypingCatalog.writes.values.flatMap { $0 } + FinderCatalog.writes.values.flatMap { $0 }
            + DockCatalog.writes.values.flatMap { $0 }
        let fullPlan = try service.read(all) { _ in nil }
        expect(fullPlan.apply.allSatisfy { $0.executable == "/usr/bin/defaults" }, "Only preference writes")
        expect(IPhoneBackupPolicy.writes(automaticBackups: false)[0].value == .bool(true), "Backup inversion")
        expect(IPhoneBackupPolicy.backupDirectory(home: home).lastPathComponent == "Backup", "Backup path")
        let profile = try AppleAppsPolicy.profile(Set(AppleAppsPolicy.Restriction.allCases),
                                                  identifier: "test.apple-apps", profileUUID: UUID(), payloadUUID: UUID())
        guard let root = try PropertyListSerialization.propertyList(from: profile, format: nil) as? [String: Any]
        else { fatalError("Profile dictionary") }
        expect(root["PayloadScope"] as? String == "System", "Restrictions require approved system profile")
        guard let payload = (root["PayloadContent"] as? [[String: Any]])?.first
        else { fatalError("Restriction payload") }
        expect(AppleAppsPolicy.Restriction.allCases.allSatisfy { payload[$0.rawValue] as? Bool == false },
               "All four restrictions encoded")
        _ = try FinderService().libraryHidden(home: FileManager.default.homeDirectoryForCurrentUser)
        print("\(checks) passed, 0 failed")
    }
}
// notchcast-sources: Tinycast/Features/Tweaks/Model/*.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
