import Foundation

extension NotchcastFeature.BackupKeys {
    static let islandHoverOpen = Self(allowed: [
        "islandHoverDelay": .choices([0.1, 0.3, 0.5, 1]),
    ], excluded: [])
}
