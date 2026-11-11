import Foundation

extension NotchcastFeature.BackupKeys {
    static let greenMaximize = Self(allowed: [
        "greenMaximizeExcludedApps": .string(16_384),
    ], excluded: [], snapshot: {
        ["greenMaximizeExcludedApps": NotchcastPreferences.shared.greenMaximizeExcludedApps]
    }, apply: { values in
        if let value = values["greenMaximizeExcludedApps"] as? String {
            NotchcastPreferences.shared.greenMaximizeExcludedApps = value
        }
    })
}
