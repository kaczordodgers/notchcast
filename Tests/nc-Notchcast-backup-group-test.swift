// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastBackupGroups.swift
import Foundation
import SwiftUI
import Observation

@Observable @MainActor final class AppCore {
    let settings: Settings
    init(defaults: UserDefaults) { settings = Settings(defaults: defaults) }
    final class Settings {
        var settingsFileEnabled: Bool
        init(defaults: UserDefaults) {
            settingsFileEnabled = defaults.bool(forKey: "settingsFileEnabled")
        }
    }
}
enum BackupCategory: Hashable { case configuration; static let all: Set<Self> = [.configuration] }
@MainActor enum BackupActions {
    static var writes: [Bool] = []
    static let settingsFilePath = "fixture/settings.json"
    static func setSettingsFileEnabled(_ value: Bool, core: AppCore) async {
        writes.append(value)
        core.settings.settingsFileEnabled = value
    }
    static func revealSettingsFile() {}
    static func runImportCommand(core: AppCore) async {}
    static func exportBackup(core: AppCore, categories: Set<BackupCategory>) async throws -> Bool { true }
    static func exportText(_ result: Bool) -> String { "fixture" }
}
struct BackupCategorySelection: View {
    @Binding var selection: Set<BackupCategory>
    var body: some View { EmptyView() }
}
enum FixtureAnchor { case notchcastBackupSettingsFile, notchcastBackupExport, notchcastBackupImport }
struct SettingsRowTitle: View {
    init(_ anchor: FixtureAnchor, _ title: String) {}
    var body: some View { EmptyView() }
}
struct SettingsSectionHeader: View {
    init(_ anchor: FixtureAnchor) {}
    var body: some View { EmptyView() }
}

@main @MainActor struct BackupGroupTest {
    static func main() async throws {
        let suite = "backup-group-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "settingsFileEnabled")
        let core = AppCore(defaults: defaults)
        _ = NotchcastBackupGroups().environment(core)
        precondition(core.settings.settingsFileEnabled)
        precondition(BackupActions.writes.isEmpty)
        let binding = NotchcastBackupGroups.settingsFileSync(core: core)
        precondition(binding.wrappedValue)
        binding.wrappedValue = false
        while BackupActions.writes.isEmpty { await Task.yield() }
        precondition(!core.settings.settingsFileEnabled)
        binding.wrappedValue = true
        while BackupActions.writes.count < 2 { await Task.yield() }
        precondition(core.settings.settingsFileEnabled)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let group = try read("Tinycast/Features/Notchcast/Settings/Tree/NotchcastBackupGroups.swift")
        precondition(group.contains("get: { core.settings.settingsFileEnabled }"))
        precondition(group.contains("await BackupActions.setSettingsFileEnabled(enabled, core: core)"))
        precondition(!group.contains("settingsFileEnabled ="))
        let settings = try read("Tinycast/Features/Settings/AppSettings.swift")
        precondition(settings.contains("settingsFileEnabled = defaults.bool(forKey: Key.settingsFileEnabled.rawValue)"))
        print("Backup group wiring and construction passed; full app launch is not exercised")
    }
}
