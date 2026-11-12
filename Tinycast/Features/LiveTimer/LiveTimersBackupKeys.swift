import Foundation

extension NotchcastFeature.BackupKeys {
    static let liveTimers = Self(allowed: [
        LiveTimerStore.durationKey: .choices(LiveTimerStore.defaultDurations),
        LiveTimerStore.soundKey: .bool,
    ], excluded: [
        LiveTimerStore.entriesKey,
    ], snapshot: {
        let store = LiveTimerModule.shared.store
        return [LiveTimerStore.durationKey: store.defaultDuration,
                LiveTimerStore.soundKey: store.playSoundWhenTimeIsUp]
    }, apply: { values in
        let store = LiveTimerModule.shared.store
        if let value = values[LiveTimerStore.durationKey] as? Double { store.defaultDuration = value }
        if let value = values[LiveTimerStore.soundKey] as? Bool { store.playSoundWhenTimeIsUp = value }
    })
}
