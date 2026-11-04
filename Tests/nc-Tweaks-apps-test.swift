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
        expect(DockCatalog.writes.count == 21, "Nine toggles plus additional Dock/window preferences")
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
        let original: [[String: Any]] = [
            ["tile-data": ["bundle-identifier": "com.apple.Music"], "GUID": 1],
            ["tile-data": ["bundle-identifier": "org.example.keep"], "GUID": 2],
            ["tile-type": "spacer-tile"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
        let dock = try AppleAppsPolicy.dockPlan(previous: data)
        guard let filtered = try PropertyListSerialization.propertyList(from: dock.replacement, format: nil)
            as? [[String: Any]] else { fatalError("Dock array") }
        expect(filtered.count == 2 && filtered[0]["GUID"] as? Int == 2, "Dock order and unknown tiles preserved")
        expect(dock.previous == data, "Exact Dock rollback snapshot")
        do {
            _ = try AppleAppsPolicy.dockPlan(previous: Data("broken".utf8))
            fatalError("Malformed Dock accepted")
        } catch { checks += 1 }
        let label = AppleAppsPolicy.musicLabel(bundleInode: 1, executableInode: 2)
        let disable = try AppleAppsPolicy.serviceCommands(musicLabel: label, userID: 501, disabled: true)
        expect(disable.count == 2 && disable[1].arguments == ["bootout", "gui/501/\(label)"], "Music disable plan")
        expect(try AppleAppsPolicy.serviceCommands(userID: 501, disabled: false)[0].arguments ==
               ["enable", "gui/501/com.apple.rcd"], "Media key revert")
        do {
            _ = try AppleAppsPolicy.serviceCommands(musicLabel: "arbitrary", userID: 501, disabled: true)
            fatalError("Invalid Music job accepted")
        } catch AppleAppsPolicy.Failure.invalidMusicLabel { checks += 1 }
        _ = try AppleAppsService().musicLabel(app: URL(fileURLWithPath: "/System/Applications/Music.app"))
        _ = try FinderService().libraryHidden(home: FileManager.default.homeDirectoryForCurrentUser)
        print("\(checks) passed, 0 failed")
    }
}
