import Foundation
import OSLog

extension ForkSettingsBackupState {
    static var live: Self {
        Self(snapshot: {
            var values = ForkSettingsBackupRestore.snapshot(.shared)
            for feature in NotchcastFeature.BackupKeys.all {
                let saved = (try? feature.snapshot()) ?? [:]
                for key in feature.allowed.keys {
                    do {
                        guard let value = saved[key] else { throw ForkSettingsBackupEngine.Failure.invalidArchive }
                        try validateLive([key: value])
                        values[key] = value
                    } catch { logSkipped(key) }
                }
            }
            return values
        }, validate: validateLive, apply: { values in
            try validateLive(values)
            for feature in NotchcastFeature.BackupKeys.all { try feature.apply(values) }
            try ForkSettingsBackupRestore.apply(values, to: .shared)
        })
    }

    private static func logSkipped(_ key: String) {
        Logger(subsystem: NotchcastIdentity.current.bundleID, category: "SettingsBackup")
            .error("Skipping invalid backup key: \(key, privacy: .public)")
    }

    private static func validateLive(_ values: [String: Any]) throws {
        try ForkSettingsBackupEngine.validate(values)
        for feature in NotchcastFeature.BackupKeys.all { try feature.validate(values) }
    }
}
