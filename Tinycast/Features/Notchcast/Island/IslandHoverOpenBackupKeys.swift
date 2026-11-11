import Foundation

extension NotchcastFeature.BackupKeys {
    static let islandHoverOpen = Self(allowed: [
        NotchcastPreferences.islandHoverDelayKey: .choices([0.1, 0.3, 0.5, 1]),
    ], excluded: [], snapshot: {
        [NotchcastPreferences.islandHoverDelayKey: NotchcastPreferences.shared.islandHoverDelay.rawValue]
    }, apply: { values in
        if let value = values[NotchcastPreferences.islandHoverDelayKey] as? NSNumber,
           let delay = NotchcastPreferences.HoverDelay(rawValue: value.doubleValue) {
            NotchcastPreferences.shared.islandHoverDelay = delay
        }
    })
}
