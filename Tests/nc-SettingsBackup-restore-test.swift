// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift
// notchcast-sources: -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist
// notchcast-sources: -Xlinker Tests/fixtures/settings-backup-info.plist
// notchcast-sources: Tinycast/Features/SettingsBackup/Service/*.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupRestore.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupState.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupCoordinator.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupModule.swift
// notchcast-kit: core host command
// notchcast-sources: Tinycast/Features/DocumentEditor/Service/EditorPreferences.swift
// notchcast-sources: Tinycast/Features/QuitProtection/Model/*.swift
// notchcast-sources: Tinycast/Features/QuitProtection/Service/QuitProtectionStore.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupState+Live.swift
// notchcast-sources: Tinycast/Features/LiveTimer/Model/*.swift
// notchcast-sources: Tinycast/Features/LiveTimer/Service/*.swift
// notchcast-sources: Tinycast/Features/LiveDay/Model/*.swift
// notchcast-sources: Tinycast/Features/LiveDay/Service/*.swift
// notchcast-sources: Tinycast/Features/LiveDay/DayWeatherModule.swift
// notchcast-sources: Tinycast/Features/LiveDay/DayMarketsModule.swift
// notchcast-sources: Tinycast/Features/LiveTimer/LiveTimerModule.swift
// notchcast-sources: Tinycast/Features/Appearance/Service/AppearanceStore.swift
// notchcast-sources: Tinycast/Features/Appearance/Model/RaycastTheme.swift
// notchcast-sources: Tinycast/Features/Appearance/Model/RaycastThemeLink.swift
// notchcast-sources: Tinycast/Features/Appearance/Model/AppearanceThemeImport.swift
// notchcast-sources: Tinycast/Features/Appearance/Model/AppearanceSurfaceStyle.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Model/DictationCleanupSettings.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Service/DictationCleanupSettingsStore.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/DictationCleanupModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastBackupKeys.swift
// notchcast-sources: Tinycast/Features/LowDisk/Model/*.swift
// notchcast-sources: Tinycast/Features/LowDisk/Service/*.swift
// notchcast-sources: Tinycast/Features/SpacesOrder/Model/*.swift
// notchcast-sources: Tinycast/Features/SpacesOrder/Service/*.swift
// notchcast-sources: Tinycast/Features/BackupStatus/Model/*.swift
// notchcast-sources: Tinycast/Features/BackupStatus/Service/*.swift
// notchcast-sources: Tinycast/Features/BackupStatus/BackupStatusModule+Live.swift
// notchcast-sources: Tinycast/Features/Microphone/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Model/LastPlayer.swift Tinycast/Features/Music/Model/NowPlaying.swift
import Foundation

enum AppPaths { static func applicationSupport() -> URL { FileManager.default.temporaryDirectory } }
enum DialogTone { case neutral, success, danger }
@MainActor final class AppCore {
    let settingsCoordinator = SettingsStub()
    static let shared = AppCore()
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async { }
    func confirm(title: String, message: String?, symbol: String?, confirmTitle: String) async -> Bool { false }
}
@MainActor final class SettingsStub {
    enum Tab { case notchcast }
    func showSettings(tab: Tab) { }
}
enum NotchcastSettingsModule {
    static func module(of feature: NotchcastFeature) -> Self { .system }
    case system
    var tab: SettingsStub.Tab { .notchcast }
}
enum SettingsActionCommands {
    @MainActor static func show(_ tab: SettingsStub.Tab, _ feature: NotchcastFeature) { }
}
@MainActor final class CalendarStub {
    var excludedCalendarIDs: Set<String> = []
    func setExcludedCalendars(_ ids: Set<String>) { excludedCalendarIDs = ids }
}
enum ColorPickerFormat: String { case hex, hexLowercase, rgb, hsl, swiftUIColor, nsColorLiteral }
enum ColorPickerService { static let formatKey = "notchcast.colorPicker.format" }
enum ScreenshotModule {
    static let destinationKey = "notchcast.screenshot.destination"
    static let folderKey = "notchcast.screenshot.folder"
}
enum SpotifyConnectModule { static let deviceNameKey = "spotify.deviceName" }
enum AgentBridgeModule { static let grantsKey = "agentActionGrants" }
enum ArchiveRecovery { static let key = "archiveRecoveryParents" }
@MainActor final class ColorPickerModule {
    static let shared = ColorPickerModule()
    var format = ColorPickerFormat.hex
}
@MainActor final class ScreenTextModule {
    static let shared = ScreenTextModule()
    nonisolated static let removeLineBreaksKey = "screenText.removeLineBreaks"
    var removeLineBreaks = false
}
extension LiveTimerModule { static let shared = LiveTimerModule() }
extension DayMarketsModule { static let shared = DayMarketsModule() }
extension DayWeatherModule { static let shared = DayWeatherModule() }
extension QuitProtectionStore { static let shared = QuitProtectionStore() }
extension DictationCleanupModule {
    static let shared = DictationCleanupModule(
        store: .live(bundleIdentifier: Bundle.main.bundleIdentifier!)!, install: { }, uninstall: { })
}
extension ForkSettingsBackupCoordinator { static let shared = ForkSettingsBackupCoordinator() }
@MainActor final class EventReminderModule {
    static let shared = EventReminderModule()
    nonisolated static let excludedCalendarsKey = "notchcast.day.excludedCalendars"
    let calendar = CalendarStub()
}
@MainActor final class EditorCoordinator {
    static let shared = EditorCoordinator()
    let editorPreferences = EditorPreferences(defaults: UserDefaults(suiteName: Bundle.main.bundleIdentifier! + ".editor")!)
}
@MainActor final class AppearanceThemeColors {
    static let shared = AppearanceThemeColors()
    func update(light: RaycastTheme?, dark: RaycastTheme?, preview: RaycastThemeLink.Target?, opacity: Double) { }
}

@MainActor final class DialogScript {
    var calls = 0
    var continuation: CheckedContinuation<Bool, Never>?
    func confirm() async -> Bool {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func answer(_ answer: Bool) { continuation?.resume(returning: answer); continuation = nil }
    func waitForDialog() async {
        while continuation == nil { await Task.yield() }
    }
}

@main struct RestoreTest {
    @MainActor static func main() async throws {
        precondition(Bundle.main.bundleIdentifier == "test.notchcast.settings-backup")
        let liveDomain = Bundle.main.bundleIdentifier! + ".notchcast"
        let liveDefaults = UserDefaults(suiteName: liveDomain)!
        liveDefaults.removePersistentDomain(forName: liveDomain)
        defer { liveDefaults.removePersistentDomain(forName: liveDomain) }
        let editorDomain = Bundle.main.bundleIdentifier! + ".editor"
        let editorDefaults = UserDefaults(suiteName: editorDomain)!
        editorDefaults.removePersistentDomain(forName: editorDomain)
        defer { editorDefaults.removePersistentDomain(forName: editorDomain) }
        let collisionDomain = "test.cleanup-collision.\(UUID().uuidString)"
        let collisionDefaults = UserDefaults(suiteName: collisionDomain)!
        defer { collisionDefaults.removePersistentDomain(forName: collisionDomain) }
        let collisionPreferences = NotchcastPreferences(suiteName: collisionDomain)
        let collisionStore = DictationCleanupSettingsStore(defaults: collisionDefaults, bundleIdentifier: collisionDomain)
        var cleanupSettings = DictationCleanupSettings()
        cleanupSettings.baseURL = "http://127.0.0.1:3425"
        collisionPreferences.set(.dictationCleanup, true)
        try collisionStore.save(cleanupSettings)
        precondition(NotchcastPreferences(suiteName: collisionDomain).isOn(.dictationCleanup))
        collisionPreferences.set(.dictationCleanup, false)
        collisionPreferences.set(.dictationCleanup, true)
        let preservedCleanup = try collisionStore.read()
        precondition(preservedCleanup == cleanupSettings)
        print("PASS: cleanup settings and feature switch persist independently")
        let complete = try ForkSettingsBackupState.live.snapshot()
        for feature: NotchcastFeature in [.urlCleaner, .dictationHistory, .captureTrimmer] {
            precondition(complete[feature.rawValue] as? Bool == NotchcastPreferences.shared.isOn(feature), feature.rawValue)
        }
        print("PASS: snapshots record urlCleaner, dictationHistory, captureTrimmer as they are")
        try ForkSettingsBackupRestore.apply(["captureTrimmer": true], to: NotchcastPreferences.shared)
        precondition(!liveDefaults.bool(forKey: "captureTrimmer"))
        precondition(!NotchcastPreferences.shared.isOn(.captureTrimmer))
        precondition(!NotchcastPreferences.shared.isEnabled(.captureTrimmer))
        print("PASS: restored captureTrimmer true stays off and disabled")
        precondition(Set(complete.keys) == Set(ForkSettingsBackupSchema.allowed.keys))
        liveDefaults.set("not theme data", forKey: "notchcast.appearance.theme.light")
        let partial = try ForkSettingsBackupState.live.snapshot()
        precondition(partial["notchcast.appearance.theme.light"] == nil && partial.count == complete.count - 1)
        liveDefaults.removeObject(forKey: "notchcast.appearance.theme.light")
        print("PASS: an unreadable theme drops only its own key from a snapshot")
        for feature in NotchcastFeature.BackupKeys.all {
            let own = try feature.snapshot()
            precondition(Set(own.keys) == Set(feature.allowed.keys), "\(feature.allowed.keys.sorted())")
        }
        print("PASS: every feature's own snapshot returns exactly the keys it allows")
        for feature in NotchcastFeature.allCases {
            precondition((ForkSettingsBackupSchema.allowed[feature.rawValue] != nil) == feature.backedUp, feature.rawValue)
            precondition(ForkSettingsBackupSchema.excluded.contains(feature.rawValue) != feature.backedUp, feature.rawValue)
        }
        print("PASS: a switch is carried or left out as its feature's backedUp flag says")
        let alertRows = try String(
            contentsOfFile: "Tinycast/Features/Notchcast/Settings/Rows/MonitorAndFansSettingRows.swift", encoding: .utf8)
        let alertKeys = try String(
            contentsOfFile: "Tinycast/Features/SystemMonitor/MonitorAlertsBackupKeys.swift", encoding: .utf8)
        precondition(alertRows.firstMatch(of: /in: \d/) == nil, "a settings row types an alert threshold's bounds itself")
        precondition(alertKeys.firstMatch(of: /\.integer\(\d/) == nil, "the backup types an alert threshold's bounds itself")
        print("PASS: the alert rows and the backup type no threshold bounds of their own")
        let secretName = /(?i)soloist|spotify|api.?key|secret|token|password/
        precondition(complete.keys.allSatisfy { $0.firstMatch(of: secretName) == nil })
        let cleanupStore = DictationCleanupSettingsStore(defaults: liveDefaults,
            bundleIdentifier: Bundle.main.bundleIdentifier!)
        var cleanup = DictationCleanupSettings()
        cleanup.isEnabled = true
        cleanup.baseURL = "http://localhost:8317"
        try cleanupStore.save(cleanup)
        let legacyCleanup = #"{"effort":"high","promptAddition":"Use commas","vocabulary":[{"spelling":"Tinycast","misheardForms":["tiny cast"]}]}"#
        let legacy = try PropertyListSerialization.data(fromPropertyList:
            ["format": 2, "created": Date.now, "preferences": ["dictationCleanup": legacyCleanup]],
            format: .binary, options: 0)
        for enabled in [false, true] {
            NotchcastPreferences.shared.set(.dictationCleanup, enabled)
            try cleanupStore.save(cleanup)
            let decoded = try ForkSettingsBackupEngine.decode(legacy)
            precondition(decoded["dictationCleanup"] == nil)
            try ForkSettingsBackupState.live.apply(decoded)
            let restored = try cleanupStore.read()
            precondition(restored.effort == .high && restored.promptAddition == "Use commas")
            precondition(restored.vocabulary.first?.spelling == "Tinycast")
            precondition(restored.vocabulary.first?.misheardForms == ["tiny cast"])
            precondition(NotchcastPreferences.shared.isOn(.dictationCleanup) == enabled)
            precondition(restored.isEnabled && restored.baseURL == cleanup.baseURL)
            precondition(DictationCleanupModule.shared.settings == restored, "live cleanup module kept a stale copy")
        }
        print("PASS: legacy cleanup archive restores settings and preserves both switch states")
        var changed = complete
        changed["notchcast.editor.font"] = "system"
        changed["notchcast.editor.theme"] = "system"
        changed["notchcast.editor.pairsAutomatically"] = false
        for (key, value) in complete where ForkSettingsBackupSchema.allowed[key].map({
            if case .bool = $0 { return true }; return false
        }) == true { changed[key] = !(value as? Bool ?? false) }
        changed["monitorCPU"] = 60
        changed["monitorTemperature"] = 80
        changed["monitorMemory"] = 1
        changed["monitorDisk"] = 20
        changed["monitorBattery"] = 25
        changed["monitorBatteryTemperature"] = 45
        changed["buildStatsPath"] = "/tmp/build.json"
        changed["greenMaximizeExcludedApps"] = "com.example.app"
        changed["islandHoverDelay"] = 1.0
        changed["notchcast.liveTimer.defaultDuration"] = 3600.0
        changed["notchcast.quitProtection.mode"] = "doublePress"
        changed["notchcast.quitProtection.exceptions"] = ["com.example.app"]
        changed["notchcast.day.marketSymbols"] = ["MSFT"]
        changed["notchcast.day.excludedCalendars"] = ["test-calendar"]
        changed["notchcast.day.weatherPlace"] = "{\"name\":\"Test\",\"country\":\"XX\",\"latitude\":20,\"longitude\":30}"
        changed["notchcast.dictationCleanup.settings"] = "{\"effort\":\"high\",\"promptAddition\":\"Use commas\",\"vocabulary\":[]}"
        changed["notchcast.colorPicker.format"] = "hsl"
        changed["notchcast.appearance.surface"] = "matte"
        changed["notchcast.appearance.theme.backgroundOpacity"] = 0.4
        let theme = "{\"name\":\"Test\",\"author\":\"Test\",\"appearance\":\"dark\",\"colors\":["
            + Array(repeating: "\"#112233\"", count: 12).joined(separator: ",") + "]}"
        changed["notchcast.appearance.theme.dark"] = theme
        changed["notchcast.appearance.theme.light"] = theme.replacingOccurrences(of: "dark", with: "light")
        changed["notchcast.appearance.themes.imported"] = "[" + theme + "]"
        let appearance = AppearanceStore()
        let revision = appearance.revision
        _ = try ForkSettingsBackupState.live.snapshot()
        precondition(appearance.revision == revision)
        try ForkSettingsBackupState.live.apply(changed)
        let editor = EditorCoordinator.shared.editorPreferences
        precondition(editor.font == .system && editor.theme == .system && !editor.pairsAutomatically)
        precondition(editorDefaults.string(forKey: "font") == "system")
        precondition(editorDefaults.string(forKey: "theme") == "system")
        precondition(editorDefaults.object(forKey: "pairsAutomatically") as? Bool == false)
        let savedLive = try ForkSettingsBackupState.live.snapshot()
        for (key, expected) in changed {
            if case .json = ForkSettingsBackupSchema.allowed[key]! {
                let actualJSON = try JSONSerialization.jsonObject(
                    with: Data((savedLive[key] as? String ?? "").utf8), options: .fragmentsAllowed)
                let expectedJSON = try JSONSerialization.jsonObject(
                    with: Data((expected as? String ?? "").utf8), options: .fragmentsAllowed)
                precondition((actualJSON as? NSObject)?.isEqual(expectedJSON) == true, key)
            } else if let feature = NotchcastFeature(rawValue: key), !feature.isWired {
                precondition(savedLive[key] as? Bool == false, key)
            } else {
                precondition(NSDictionary(dictionary: [key: savedLive[key]!])
                    == NSDictionary(dictionary: [key: expected]), key)
            }
        }
        try ForkSettingsBackupState.live.apply(complete)
        precondition(editor.font == .jetBrainsMono && editor.theme == .githubDark && editor.pairsAutomatically)
        try ForkSettingsBackupState.live.apply(ForkSettingsBackupEngine.decode(
            ForkSettingsBackupEngine.encode(savedLive, created: .now)))
        let restoredLive = try ForkSettingsBackupState.live.snapshot()
        precondition(restoredLive["monitorBatteryTemperature"] as? Int == 45)
        for (key, expected) in savedLive {
            if case .json = ForkSettingsBackupSchema.allowed[key]! {
                let actual = try JSONSerialization.jsonObject(
                    with: Data((restoredLive[key] as? String ?? "").utf8), options: .fragmentsAllowed)
                let wanted = try JSONSerialization.jsonObject(
                    with: Data((expected as? String ?? "").utf8), options: .fragmentsAllowed)
                precondition((actual as? NSObject)?.isEqual(wanted) == true, key)
            } else {
                precondition(NSDictionary(dictionary: [key: restoredLive[key]!])
                    == NSDictionary(dictionary: [key: expected]), key)
            }
        }
        precondition(appearance.imported.count == 1)
        let preserved = try cleanupStore.read()
        precondition(preserved.isEnabled && preserved.baseURL == cleanup.baseURL)
        for field in ["isEnabled", "baseURL"] {
            let bad = (changed["notchcast.dictationCleanup.settings"] as? String ?? "").dropLast() + ",\"\(field)\":true}"
            do { try ForkSettingsBackupState.live.apply(["notchcast.dictationCleanup.settings": String(bad)]); preconditionFailure() } catch { }
        }
        for bad in [Data("broken".utf8), try JSONEncoder().encode(DictationCleanupSettings(
            promptAddition: String(repeating: "x", count: 16_385)))] {
            liveDefaults.set(bad, forKey: "dictationCleanupSettings")
            let snapshot = try ForkSettingsBackupState.live.snapshot()
            precondition(snapshot["notchcast.dictationCleanup.settings"] == nil && snapshot.count == complete.count - 1)
            let badFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: badFolder) }
            let encoded = try ForkSettingsBackupEngine.encode(snapshot, created: .now)
            try await ForkSettingsBackupService.save(encoded, folder: badFolder, day: 1)
            let written = try await ForkSettingsBackupService.read(folder: badFolder, name: "settings-v2-1.plist")
            precondition(written == encoded)
        }
        print("PASS: isolated live round trip, cleanup destination preserved, invalid key skipped")
        let statusFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: statusFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: statusFolder) }
        let statusFiles = try ["first", "restored", "typed"].map { name in
            let folder = statusFolder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent("status.json")
        }
        var statusNotices = 0
        func statusNoticed(_ count: Int) async -> Bool {
            for _ in 0..<200 where statusNotices < count { try? await Task.sleep(for: .milliseconds(50)) }
            return statusNotices == count
        }
        NotchcastPreferences.shared.backupStatusPath = statusFiles[0].path
        let backupStatus = BackupStatusModule(path: { NotchcastPreferences.shared.backupStatusPath },
                                              post: { _ in statusNotices += 1 })
        backupStatus.start()
        let missingFileNoticed = await statusNoticed(1)
        precondition(missingFileNoticed)
        try ForkSettingsBackupState.live.apply(["backupStatusPath": statusFiles[1].path])
        let restoredPathRead = await statusNoticed(2)
        precondition(restoredPathRead, "Backup Status did not restart on a restored path")
        let stamp = ISO8601DateFormatter().string(from: .now)
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "result": "failed", "message": NSNull(), "lastSuccess": stamp, "lastAttempt": stamp,
            "snapshotCount": 8, "oldestSnapshot": stamp, "newestSnapshot": stamp, "sourceBytes": 1000,
            "addedBytes": 100, "repoBytes": 2000, "targetFreeBytes": 3000, "lowSpace": false,
            "retention": "Last 2", "restoreTest": ["at": stamp, "result": "ok"],
            "mbpTimeMachine": ["latest": stamp, "checkedAt": stamp, "error": NSNull()],
        ] as [String: Any]).write(to: statusFiles[1])
        let restoredFileWatched = await statusNoticed(3)
        precondition(restoredFileWatched, "Backup Status kept watching the folder from before the restore")
        NotchcastPreferences.shared.backupStatusPath = statusFiles[2].path
        let writtenPathRead = await statusNoticed(4)
        precondition(writtenPathRead, "Backup Status missed a write to its path")
        backupStatus.stop()
        print("PASS: Backup Status watches a restored path and restarts on every later write to it")
        let suite = "test.settings-restore"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let store = QuitProtectionStore(defaults: defaults)
        let state = ForkSettingsBackupState(snapshot: {
            ForkSettingsBackupRestore.snapshot(preferences).merging(store.backupValues) { _, new in new }
                .merging(preferences.monitorAlertsBackupValues) { _, new in new }
        }, validate: ForkSettingsBackupEngine.validate, apply: {
            try ForkSettingsBackupEngine.validate($0)
            try ForkSettingsBackupRestore.apply($0, to: preferences)
            store.applyBackup($0)
            preferences.applyMonitorAlertsBackup($0)
        })
        let saved = try state.snapshot()
        for feature: NotchcastFeature in [.musicNowPlaying, .musicLastPlayer, .inUseMarks,
                                        .urlCleaner, .dictationHistory, .captureTrimmer] {
            let original = preferences.isOn(feature)
            preferences.set(feature, !original)
            let captured = try state.snapshot()
            let restored = feature.isWired && !original
            precondition(captured[feature.rawValue] as? Bool == restored, "saved a value restore never sets")
            preferences.set(feature, original)
            try state.apply(captured)
            let roundTrip = try state.snapshot()
            precondition(roundTrip as NSDictionary == captured as NSDictionary, "a saved key was not restored")
            precondition(preferences.isOn(feature) == restored)
            precondition(defaults.bool(forKey: feature.rawValue) == restored)
            preferences.set(feature, original)
        }
        precondition(saved["monitorCPU"] as? Int == 90)
        precondition(saved["island"] as? Bool == preferences.isOn(.island))
        precondition(saved["notchcast.quitProtection.quitEnabled"] as? Bool == true)
        preferences.monitorCPU = 50
        preferences.set(.island, false)
        store.configuration.quitEnabled = false
        try state.apply(ForkSettingsBackupEngine.decode(ForkSettingsBackupEngine.encode(saved, created: .now)))
        precondition(preferences.monitorCPU == 90 && preferences.isOn(.island) && store.configuration.quitEnabled)
        precondition(defaults.integer(forKey: "monitorCPU") == 90 && defaults.bool(forKey: "island"))
        precondition(defaults.bool(forKey: "notchcast.quitProtection.quitEnabled"))
        preferences.greenMaximizeExcludedApps = "com.example.app"
        preferences.fanMode = "manual"
        preferences.batteryChargePercent = 90
        for feature in NotchcastFeature.allCases where ForkSettingsBackupSchema.excluded.contains(feature.rawValue) {
            preferences.set(feature, false)
        }
        let before = defaults.persistentDomain(forName: suite)! as NSDictionary
        let current = try state.snapshot() as NSDictionary
        for key in ForkSettingsBackupSchema.excluded.union(["future"]) {
            do { try state.apply(["monitorCPU": 75, key: true]); preconditionFailure("Accepted excluded key") } catch { }
            precondition(defaults.persistentDomain(forName: suite)! as NSDictionary == before)
            let after = try state.snapshot() as NSDictionary
            precondition(after == current)
        }
        for values: [String: Any] in [["monitorCPU": "bad"], ["monitorCPU": 101],
                                     ["keepAwakeMinutes": 45], ["islandHoverDelay": 0.4],
                                     ["notchcast.quitProtection.mode": "future"],
                                     ["notchcast.day.marketSymbols": [String(repeating: "x", count: 65)]],
                                     ["notchcast.dictationCleanup.settings": "{\"apiKey\":\"secret\"}"]] {
            do { try state.apply(values); preconditionFailure("Accepted invalid value") } catch { }
            precondition(defaults.persistentDomain(forName: suite)! as NSDictionary == before)
        }
        let future = try PropertyListSerialization.data(fromPropertyList:
            ["format": 3, "created": Date.now, "preferences": ["monitorCPU": 70]], format: .binary, options: 0)
        for invalid in [Data(), Data("broken".utf8), future] {
            do {
                try state.apply(ForkSettingsBackupEngine.decode(invalid))
                preconditionFailure("Accepted corrupt or future archive")
            } catch { }
            precondition(defaults.persistentDomain(forName: suite)! as NSDictionary == before)
            let after = try state.snapshot() as NSDictionary
            precondition(after == current)
        }
        try state.apply(["monitorCPU": 75])
        precondition(preferences.greenMaximizeExcludedApps == "com.example.app" && preferences.fanMode == "manual")
        precondition(preferences.batteryChargePercent == 90)
        for feature in NotchcastFeature.allCases where ForkSettingsBackupSchema.excluded.contains(feature.rawValue) {
            precondition(!preferences.isOn(feature))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try ForkSettingsBackupEngine.encode(saved, created: .now)
        try await ForkSettingsBackupService.save(data, folder: folder, day: 1)
        let script = DialogScript()
        let newer = try ForkSettingsBackupEngine.encode(["monitorCPU": 60], created: .now.addingTimeInterval(60))
        try await ForkSettingsBackupService.save(newer, folder: folder, day: 3)
        let validCopies = try await ForkSettingsBackupService.copies(folder: folder)
        precondition(validCopies.map(\.name) == ["settings-v2-3.plist", "settings-v2-1.plist"])
        var reports: [Bool] = []
        let coordinator = ForkSettingsBackupCoordinator(folder: folder, state: state,
            confirm: { await script.confirm() }, report: { reports.append($0) })
        coordinator.restore()
        await coordinator.settled()
        precondition(coordinator.choosing)
        coordinator.restore(name: "settings-v2-1.plist")
        await script.waitForDialog()
        coordinator.restore(name: "settings-v2-1.plist")
        for _ in 0..<100 { await Task.yield() }
        precondition(script.calls == 1)
        script.answer(false)
        await coordinator.settled()
        precondition(preferences.monitorCPU == 75 && reports.isEmpty && !coordinator.choosing)
        coordinator.restore()
        await coordinator.settled()
        coordinator.cancelChoosing()
        precondition(!coordinator.choosing)
        coordinator.restore()
        await coordinator.settled()
        coordinator.restore(name: "settings-v2-1.plist")
        await script.waitForDialog()
        coordinator.stop()
        script.answer(true)
        await coordinator.settled()
        precondition(preferences.monitorCPU == 75 && reports.isEmpty)
        coordinator.restore()
        await coordinator.settled()
        precondition(coordinator.choosing)
        coordinator.restore(name: "settings-v2-1.plist")
        await script.waitForDialog()
        script.answer(true)
        await coordinator.settled()
        precondition(preferences.monitorCPU == 90 && reports == [true] && !coordinator.choosing)
        precondition(preferences.fanMode == "manual" && preferences.batteryChargePercent == 90)
        for feature in NotchcastFeature.allCases where ForkSettingsBackupSchema.excluded.contains(feature.rawValue) {
            precondition(!preferences.isOn(feature))
        }
        try Data("broken".utf8).write(to: folder.appendingPathComponent("settings-v2-2.plist"))
        let listed = try await ForkSettingsBackupService.copies(folder: folder)
        precondition(listed.count == 3 && listed.filter(\.valid).map(\.name)
            == ["settings-v2-3.plist", "settings-v2-1.plist"])
        coordinator.restore(name: "settings-v2-2.plist")
        await coordinator.settled()
        precondition(script.calls == 3 && reports == [true, false])
        precondition(preferences.monitorCPU == 90)
        print("PASS: copies sorted newest first; chosen older copy restored; invalid copy leaves settings unchanged")
        print("PASS: effective defaults restored (90 after 50), default switch and real store reach memory/defaults")
        print("PASS: root/consent keys unchanged; absent keys untouched; invalid values rejected before writes")
        print("PASS: coordinator declined/cancelled/reentrant/corrupt/success flows")
    }
}
