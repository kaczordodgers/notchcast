import Foundation

@main
struct TimerRecoveryTest {
    @MainActor static func main() {
        let suite = "timer-recovery-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("invalid timers".utf8)
        defaults.set(corrupt, forKey: LiveTimerStore.entriesKey)
        var now = Date()
        var sounds = 0
        var stops = 0
        let store = LiveTimerStore(defaults: defaults, clock: { now },
                                   playSound: { sounds += 1 }, stopSound: { stops += 1 })
        let timer = store.start(1)!
        precondition(defaults.dictionaryRepresentation().contains {
            $0.key.hasPrefix(LiveTimerStore.entriesKey + ".corrupt.") && ($0.value as? Data) == corrupt
        }, "Unrecoverable timer bytes survive the first mutation")
        now = now.addingTimeInterval(302)
        store.refresh()
        precondition(store.timers.first?.status == .missed && sounds == 1)
        store.refresh()
        precondition(sounds == 1, "Missed timers alert once")
        store.stopNext()
        precondition(!store.timers.contains { $0.id == timer }, "Stop Timer dismisses missed entries")
        store.start(1)
        now = now.addingTimeInterval(2)
        store.refresh()
        precondition(store.isRinging)
        let before = stops
        let played = sounds
        store.playSoundWhenTimeIsUp = false
        precondition(stops > before && store.isRinging)
        now = now.addingTimeInterval(3)
        store.refresh()
        precondition(sounds == played, "Disabling sound silences a running alert")
        store.stop()
        print("PASS corrupt-byte recovery, missed alert and dismissal, sound disabled while ringing")
    }
}
