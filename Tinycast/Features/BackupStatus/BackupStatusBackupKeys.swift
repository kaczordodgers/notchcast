import Foundation

extension NotchcastFeature.BackupKeys {
    static let backupStatus = Self(allowed: [
        "backupStatusPath": .string(4096),
    ], excluded: [], snapshot: {
        ["backupStatusPath": NotchcastPreferences.shared.backupStatusPath]
    }, apply: { values in
        if let value = values["backupStatusPath"] as? String { NotchcastPreferences.shared.backupStatusPath = value }
    })
}
