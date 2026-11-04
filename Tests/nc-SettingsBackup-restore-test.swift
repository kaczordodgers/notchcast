// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/Service/*.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupRestore.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupState.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupCoordinator.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
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
import Foundation

@MainActor protocol NotchcastModule { func start(); func stop() }
enum AppPaths { static func applicationSupport() -> URL { FileManager.default.temporaryDirectory } }
enum DialogTone { case neutral, danger }
@MainActor final class AppCore {
    static let shared = AppCore()
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async { }
    func confirm(title: String, message: String?, symbol: String?, confirmTitle: String) async -> Bool { false }
    func showMessage(_ message: String, tone: DialogTone = .neutral) { }
}
@MainActor final class CalendarStub {
    var excludedCalendarIDs: Set<String> = []
    func setExcludedCalendars(_ ids: Set<String>) { excludedCalendarIDs = ids }
}
@MainActor struct ReminderStub { let calendar = CalendarStub() }
@MainActor enum NotchcastCore {
    static let settingsBackupRestore = ForkSettingsBackupCoordinator()
    static let timers = LiveTimerModule()
    static let markets = DayMarketsModule()
    static let weather = DayWeatherModule()
    static let quitProtection = QuitProtectionStore()
    static let eventReminder = ReminderStub()
}
@MainActor final class AppearanceThemeColors {
    static let shared = AppearanceThemeColors()
    func update(light: RaycastTheme?, dark: RaycastTheme?, preview: RaycastThemeLink.Target?, opacity: Double) { }
}
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
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
        let complete = try ForkSettingsBackupState.live.snapshot()
        precondition(Set(complete.keys) == Set(ForkSettingsBackupSchema.allowed.keys))
        let suite = "test.settings-restore." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
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
        preferences.batteryChargePercent = 95
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
        try state.apply(["monitorCPU": 75])
        precondition(preferences.greenMaximizeExcludedApps == "com.example.app" && preferences.fanMode == "manual")
        precondition(preferences.batteryChargePercent == 95)
        for feature in NotchcastFeature.allCases where ForkSettingsBackupSchema.excluded.contains(feature.rawValue) {
            precondition(!preferences.isOn(feature))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try ForkSettingsBackupEngine.encode(saved, created: .now)
        try await ForkSettingsBackupService.save(data, folder: folder, day: 1)
        let script = DialogScript()
        var reports: [Bool] = []
        let coordinator = ForkSettingsBackupCoordinator(folder: folder, state: state,
            confirm: { await script.confirm() }, report: { reports.append($0) },
            missing: { preconditionFailure("Missing backup") })
        coordinator.restore()
        await script.waitForDialog()
        coordinator.restore()
        for _ in 0..<100 { await Task.yield() }
        precondition(script.calls == 1)
        script.answer(false)
        await coordinator.settled()
        precondition(preferences.monitorCPU == 75 && reports.isEmpty)
        coordinator.restore()
        await script.waitForDialog()
        coordinator.stop()
        script.answer(true)
        await coordinator.settled()
        precondition(preferences.monitorCPU == 75 && reports.isEmpty)
        coordinator.restore()
        await script.waitForDialog()
        script.answer(true)
        await coordinator.settled()
        precondition(preferences.monitorCPU == 90 && reports == [true])
        precondition(preferences.fanMode == "manual" && preferences.batteryChargePercent == 95)
        for feature in NotchcastFeature.allCases where ForkSettingsBackupSchema.excluded.contains(feature.rawValue) {
            precondition(!preferences.isOn(feature))
        }
        try Data("broken".utf8).write(to: folder.appendingPathComponent("settings-v2-2.plist"))
        coordinator.restore()
        await coordinator.settled()
        precondition(script.calls == 3 && reports == [true, false])
        print("PASS: effective defaults restored (90 after 50), default switch and real store reach memory/defaults")
        print("PASS: root/consent keys unchanged; absent keys untouched; invalid values rejected before writes")
        print("PASS: coordinator declined/cancelled/reentrant/corrupt/success flows")
    }
}
