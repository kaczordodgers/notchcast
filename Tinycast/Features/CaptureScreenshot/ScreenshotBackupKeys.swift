import Foundation

extension NotchcastFeature.BackupKeys {
    static let screenshot = Self(allowed: [:], excluded: [
        ScreenshotModule.destinationKey,
        ScreenshotModule.folderKey,
    ])
}
