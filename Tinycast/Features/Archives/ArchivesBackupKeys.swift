import Foundation

extension NotchcastFeature.BackupKeys {
    static let archives = Self(allowed: [:], excluded: [
        "archiveHandlersClaimed",
        "archiveRecoveryParents",
    ])
}
