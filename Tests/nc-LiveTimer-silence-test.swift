import Foundation

@main
struct LiveTimerSilenceTest {
    @MainActor static func main() {
        let suite = "live-timer-silence-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var instant = Date(timeIntervalSince1970: 1_000)
        var plays = 0
        var stops = 0
        let store = LiveTimerStore(defaults: defaults, clock: { instant },
                                   playSound: { plays += 1 }, stopSound: { stops += 1 })
        let running = store.start(600)!
        let stopsBeforeIdleSilence = stops
        store.silence()
        precondition(store.timers.map(\.id) == [running] && stops == stopsBeforeIdleSilence)
        let first = store.start(10)!
        let second = store.start(20)!
        instant = instant.addingTimeInterval(21)
        store.refresh()
        precondition(Set(store.ringing.map(\.id)) == [first, second] && plays == 1)
        let stopsBeforeSilence = stops
        store.silence()
        precondition(!store.isRinging && stops > stopsBeforeSilence)
        precondition(store.timers.map(\.id) == [running] && store.nextTimer?.id == running)
        instant = instant.addingTimeInterval(5)
        store.refresh()
        precondition(plays == 1)
        let unattended = store.start(1)!
        instant = instant.addingTimeInterval(1)
        store.refresh()
        precondition(store.ringing.first?.id == unattended && plays == 2)
        instant = instant.addingTimeInterval(300)
        store.refresh()
        precondition(!store.isRinging && store.timers.first { $0.id == unattended }?.status == .missed)
        store.stop()
        print("PASS silence stops every ringing timer, keeps running ones, idles as a no-op, 5 min auto-end")
    }
}
