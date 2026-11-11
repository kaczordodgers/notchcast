import Foundation

extension NotchcastFeature.BackupKeys {
    static let greenMaximize = Self(allowed: [
        NotchcastPreferences.greenMaximizeExcludedAppsKey: .string(16_384),
    ], excluded: [], snapshot: {
        [NotchcastPreferences.greenMaximizeExcludedAppsKey: NotchcastPreferences.shared.greenMaximizeExcludedApps]
    }, apply: { values in
        if let value = values[NotchcastPreferences.greenMaximizeExcludedAppsKey] as? String {
            NotchcastPreferences.shared.greenMaximizeExcludedApps = value
        }
    })
}
