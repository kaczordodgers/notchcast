// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift Tinycast/Features/SettingsBackup/Service/*.swift Tinycast/Features/SettingsBackup/ForkSettingsBackupRestore.swift Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupModule.swift Tinycast/Features/SettingsBackup/ForkSettingsBackupCommands.swift
import Foundation

enum NotchcastFeature: String, CaseIterable { case settingsBackup; var defaultEnabled: Bool { true } }
@MainActor protocol NotchcastModule { func start(); func stop() }
enum AppPaths { static func applicationSupport() -> URL { FileManager.default.temporaryDirectory } }
enum DialogTone { case neutral, danger }
@MainActor final class AppCore {
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async { }
    func confirm(title: String, message: String?, symbol: String?, confirmTitle: String) async -> Bool { false }
    func showMessage(_ message: String, tone: DialogTone = .neutral) { }
}
@MainActor enum NotchcastCore { static var settingsBackupRestore: ForkSettingsBackupCoordinator? }
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let run: @MainActor @Sendable () -> Void
}

@main
struct RestoreTest {
    @MainActor
    static func main() async throws {
        let suite = "test.settings-restore." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let saved: [String: Any] = ["monitorCPU": 75, "monitorTemperature": 85,
            "monitorMemory": 0, "monitorDisk": 12, "monitorBattery": 20,
            "batteryChargePercent": 90, "keepAwakeMinutes": 120, "islandHoverDelay": 0.5]
        let data = try ForkSettingsBackupEngine.encode(saved, created: .now)
        ForkSettingsBackupRestore.apply(try ForkSettingsBackupEngine.decode(data), to: preferences)
        func snapshot() -> [Int] {
            [preferences.monitorCPU, preferences.monitorTemperature, preferences.monitorMemory,
             preferences.monitorDisk, preferences.monitorBattery, preferences.batteryChargePercent,
             preferences.keepAwakeMinutes, Int(preferences.islandHoverDelay.rawValue * 100)]
        }
        precondition(snapshot() == [75, 85, 0, 12, 20, 90, 120, 50])
        for (key, value) in saved {
            precondition(defaults.object(forKey: key) as? NSNumber == value as? NSNumber)
        }
        let before = snapshot()
        let domain = defaults.persistentDomain(forName: suite)! as NSDictionary
        for invalid in [Data("broken".utf8), Data(), try archive(saved, format: 2),
                        try archive(["monitorCPU": 101])] {
            do {
                ForkSettingsBackupRestore.apply(try ForkSettingsBackupEngine.decode(invalid), to: preferences)
                preconditionFailure("Accepted invalid backup")
            } catch { }
            precondition(snapshot() == before)
            precondition(domain == defaults.persistentDomain(forName: suite)! as NSDictionary)
        }
        precondition(ForkSettingsBackupEngine.newest(in: ["settings-999.plist", "settings-20000.plist",
            "settings-x.plist", "other-30000.plist"]) == "settings-20000.plist")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await ForkSettingsBackupService.save(data, folder: folder, day: 999)
        try await ForkSettingsBackupService.save(Data(), folder: folder, day: 20000)
        let latest = try await ForkSettingsBackupService.latest(folder: folder)!
        do {
            _ = try ForkSettingsBackupEngine.decode(latest)
            preconditionFailure("Fell back to older backup")
        } catch { }
        precondition(snapshot() == before)
        precondition(domain == defaults.persistentDomain(forName: suite)! as NSDictionary)
        ForkSettingsBackupRestore.apply(try ForkSettingsBackupEngine.decode(archive([
            "batteryChargePercent": 81, "keepAwakeMinutes": 45, "islandHoverDelay": 0.4])), to: preferences)
        precondition(preferences.batteryChargePercent == 80 && preferences.keepAwakeMinutes == 60)
        precondition(preferences.islandHoverDelay == .standard && preferences.monitorCPU == 75)
        precondition(defaults.integer(forKey: "batteryChargePercent") == 80)
        precondition(defaults.integer(forKey: "keepAwakeMinutes") == 60)
        precondition(defaults.double(forKey: "islandHoverDelay") == 0.3)
        print("PASS: real preferences round trip in memory/defaults; four invalid archives unchanged")
        print("PASS: numeric newest; bad newest refused; omitted keys untouched; setter normalization")
    }

    static func archive(_ values: [String: Any], format: Int = 1) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["format": format, "created": Date.now,
            "preferences": values], format: .binary, options: 0)
    }
}
