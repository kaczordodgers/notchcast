import Foundation

extension NotchcastFeature.BackupKeys {
    static let greenMaximize = Self(allowed: [
        "greenMaximizeExcludedApps": .string(16_384),
    ], excluded: [])
}
