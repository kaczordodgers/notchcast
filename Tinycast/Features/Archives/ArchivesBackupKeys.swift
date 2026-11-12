import Foundation

extension NotchcastFeature.BackupKeys {
    @MainActor static let archives = Self(allowed: [:], excluded: [
        NotchcastPreferences.archiveHandlersClaimedKey,
        ArchiveRecovery.key,
    ])
}
