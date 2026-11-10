// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift
// notchcast-sources: -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist
// notchcast-sources: -Xlinker Tests/fixtures/settings-backup-info.plist
// notchcast-sources: Tinycast/Features/SettingsBackup/Service/*.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupRestore.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupState.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupCoordinator.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/DocumentEditor/Service/EditorPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
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
import Foundation

@MainActor protocol NotchcastModule { func start(); func stop() }
enum AppPaths { static func applicationSupport() -> URL { FileManager.default.temporaryDirectory } }
enum DialogTone { case neutral, danger }
@MainActor final class AppIndexStub { func refreshNotchcastCommands() { } }
@MainActor final class AppCore {
    let settingsCoordinator = SettingsStub()
    static let shared = AppCore()
    let appIndex = AppIndexStub()
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async { }
    func confirm(title: String, message: String?, symbol: String?, confirmTitle: String) async -> Bool { false }
    func showMessage(_ message: String, tone: DialogTone = .neutral) { }
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
@MainActor final class ColorPickerModule {
    static let shared = ColorPickerModule()
    var format = ColorPickerFormat.hex
}
@MainActor final class ScreenTextModule {
    static let shared = ScreenTextModule()
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
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let run: @MainActor @Sendable () -> Void
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
        let suite = "test.settings-restore"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let store = QuitProtectionStore(defaults: defaults)
        let state = ForkSettingsBackupState(snapshot: {
            ForkSettingsBackupRestore.snapshot(preferences).merging(ForkSettingsBackupState.quitValues(store)) { _, new in new }
        }, validate: ForkSettingsBackupEngine.validate, apply: {
            try ForkSettingsBackupEngine.validate($0)
            try ForkSettingsBackupRestore.apply($0, to: preferences)
            ForkSettingsBackupState.applyQuit($0, to: store)
        })
        let saved = try state.snapshot()
        for feature: NotchcastFeature in [.musicNowPlaying, .musicLastPlayer, .inUseMarks,
                                        .urlCleaner, .dictationHistory, .captureTrimmer] {
            let original = preferences.isOn(feature)
            preferences.set(feature, !original)
            let captured = try state.snapshot()
            precondition(captured[feature.rawValue] as? Bool == !original)
            preferences.set(feature, original)
            try state.apply(captured)
            let restored = feature.isWired && !original
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
                                     ["keepAwakeMinutes": 45], ["islandHoverDelay": 0.4]] {
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
