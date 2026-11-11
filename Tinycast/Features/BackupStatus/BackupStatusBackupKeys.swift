import Foundation

extension NotchcastFeature.BackupKeys {
    static let backupStatus = Self(allowed: [
        NotchcastPreferences.backupStatusPathKey: .string(4096),
    ], excluded: [], snapshot: {
        [NotchcastPreferences.backupStatusPathKey: NotchcastPreferences.shared.backupStatusPath]
    }, apply: { values in
        guard let value = values[NotchcastPreferences.backupStatusPathKey] as? String else { return }
        NotchcastPreferences.shared.backupStatusPath = value
    })
}
