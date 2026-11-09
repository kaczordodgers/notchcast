import Foundation

extension NotchcastFeature.BackupKeys {
    static let backupStatus = Self(allowed: [
        "backupStatusPath": .string(4096),
    ], excluded: [])
}
