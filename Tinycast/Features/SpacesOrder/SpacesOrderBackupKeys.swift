import Foundation

extension NotchcastFeature.BackupKeys {
    static let spacesOrder = Self(allowed: [:], excluded: [
        SpacesOrderModule.backupKey,
    ])
}
