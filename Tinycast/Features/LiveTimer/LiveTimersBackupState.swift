extension NotchcastBackupState {
    static let liveTimers = Self(snapshot: {
        let store = LiveTimerModule.shared.store
        return ["notchcast.liveTimer.defaultDuration": store.defaultDuration,
                "notchcast.liveTimer.playSound": store.playSoundWhenTimeIsUp]
    }, apply: { values in
        let store = LiveTimerModule.shared.store
        if let value = values["notchcast.liveTimer.defaultDuration"] as? Double { store.defaultDuration = value }
        if let value = values["notchcast.liveTimer.playSound"] as? Bool { store.playSoundWhenTimeIsUp = value }
    })
}
