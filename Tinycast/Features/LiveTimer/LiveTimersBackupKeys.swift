import Foundation

extension NotchcastFeature.BackupKeys {
    static let liveTimers = Self(allowed: [
        "notchcast.liveTimer.defaultDuration": .choices([300, 600, 900, 1500, 1800, 3600]),
        "notchcast.liveTimer.playSound": .bool,
    ], excluded: [
        "notchcast.liveTimer.entries",
    ], snapshot: {
        let store = LiveTimerModule.shared.store
        return ["notchcast.liveTimer.defaultDuration": store.defaultDuration,
                "notchcast.liveTimer.playSound": store.playSoundWhenTimeIsUp]
    }, apply: { values in
        let store = LiveTimerModule.shared.store
        if let value = values["notchcast.liveTimer.defaultDuration"] as? Double { store.defaultDuration = value }
        if let value = values["notchcast.liveTimer.playSound"] as? Bool { store.playSoundWhenTimeIsUp = value }
    })
}
