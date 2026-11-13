// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift
// notchcast-sources: -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist
// notchcast-sources: -Xlinker Tests/fixtures/settings-backup-status-info.plist
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
// notchcast-sources: Tests/Kit/SettingsBackupRestoreFixture.swift
import Foundation

@main struct BackupStatusRestoreTest {
    @MainActor static func main() async throws {
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
    }
}
