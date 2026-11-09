import Foundation

extension NotchcastFeature.BackupKeys {
    static let liveTimers = Self(allowed: [
        "notchcast.liveTimer.defaultDuration": .choices([300, 600, 900, 1500, 1800, 3600]),
        "notchcast.liveTimer.playSound": .bool,
    ], excluded: [
        "notchcast.liveTimer.entries",
    ])
}
