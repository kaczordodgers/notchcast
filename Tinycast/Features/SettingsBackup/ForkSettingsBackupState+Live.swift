import Foundation
import OSLog

extension ForkSettingsBackupState {
    static var live: Self {
        Self(snapshot: { liveSnapshot().values }, validate: validateLive, apply: { values in
            try validateLive(values)
            for feature in NotchcastFeature.BackupKeys.all { try feature.apply(values) }
            try ForkSettingsBackupRestore.apply(values, to: .shared)
        })
    }

    /// `skipped` names every key left out, so a partial copy is never reported as a whole one.
    static func liveSnapshot() -> (values: [String: Any], skipped: [String]) {
        var values = ForkSettingsBackupRestore.snapshot(.shared)
        var skipped: [String] = []
        for feature in NotchcastFeature.BackupKeys.all {
            let saved: [String: Any]
            do { saved = try feature.snapshot() } catch {
                let keys = feature.allowed.keys.sorted()
                let reason = String(describing: error)
                logger.error("Backup snapshot of \(keys, privacy: .public) failed: \(reason, privacy: .public)")
                skipped += keys
                continue
            }
            for key in feature.allowed.keys {
                do {
                    guard let value = saved[key] else { throw ForkSettingsBackupEngine.Failure.invalidArchive }
                    try validateLive([key: value])
                    values[key] = value
                } catch {
                    logger.error("Skipping invalid backup key: \(key, privacy: .public)")
                    skipped.append(key)
                }
            }
        }
        return (values, skipped)
    }

    private static var logger: Logger {
        Logger(subsystem: NotchcastIdentity.current.bundleID, category: "SettingsBackup")
    }

    private static func validateLive(_ values: [String: Any]) throws {
        try ForkSettingsBackupEngine.validate(values)
        for feature in NotchcastFeature.BackupKeys.all { try feature.validate(values) }
    }
}
