import Foundation

@main
struct LiveTimerTest {
    @MainActor static func main() {
        for (input, seconds) in [("5", 300.0), ("5m", 300), ("1h 30m", 5400), ("90s", 90), ("99h", 356400)] {
            precondition(LiveTimerInput.duration(input) == seconds)
        }
        for input in ["", "0", "-5", "100h", "1m garbage", "999999999999999999999999999999999999999999h"] {
            precondition(LiveTimerInput.duration(input) == nil)
        }
        precondition(LiveTimerInput.label(String(repeating: "🫖", count: 50)).count == 40)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))!
        let alarm = LiveTimerInput.alarm("7:30", now: now, calendar: calendar)!
        precondition(alarm.timeIntervalSince(now) == 23.5 * 3600)
        precondition(LiveTimerInput.alarm("24:00", now: now, calendar: calendar) == nil)
        precondition(LiveTimerInput.alarm("19:30", now: now, calendar: calendar)!.timeIntervalSince(now) == 11.5 * 3600)
        let suite = "live-timer-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var instant = now
        var sounds = 0
        let store = LiveTimerStore(defaults: defaults, clock: { instant }, calendar: { calendar },
                                   playSound: { sounds += 1 }, stopSound: {})
        precondition(store.playSoundWhenTimeIsUp)
        let later = store.start(120)!
        let sooner = store.start(60)!
        precondition(store.nextTimer?.id == sooner)
        precondition(store.timers.first?.countdown(at: now) == "1:00")
        instant = now.addingTimeInterval(61)
        store.refresh()
        precondition(store.ringing.first?.id == sooner && sounds == 1)
        store.refresh()
        precondition(sounds == 1)
        instant = now.addingTimeInterval(63)
        store.refresh()
        precondition(sounds == 2)
        store.dismiss(sooner)
        precondition(!store.isRinging)
        precondition(store.timers.first?.id == later)
        instant = now.addingTimeInterval(420)
        store.refresh()
        precondition(store.timers.first { $0.id == later }?.status == .missed)
        precondition(sounds == 2)
        store.cancel(later)
        let sleeping = store.start(1)!
        instant = instant.addingTimeInterval(302)
        store.refresh()
        precondition(store.timers.first { $0.id == sleeping }?.status == .missed)
        let ringingDuringSleep = store.start(1)!
        instant = instant.addingTimeInterval(1)
        store.refresh()
        precondition(store.isRinging)
        instant = instant.addingTimeInterval(300)
        store.refresh()
        precondition(!store.isRinging)
        precondition(store.timers.first { $0.id == ringingDuringSleep }?.status == .missed)
        store.dismiss(sleeping)
        store.dismiss(ringingDuringSleep)
        precondition(store.timers.isEmpty)
        let savedTimer = store.start(60, label: "Tea")!
        let savedAlarm = store.startAlarm("19:30", label: "Dinner")!
        store.stop()
        instant = instant.addingTimeInterval(360)
        let restored = LiveTimerStore(defaults: defaults, clock: { instant }, calendar: { calendar },
                                      playSound: { sounds += 1 }, stopSound: {})
        precondition(restored.timers.map(\.id) == [savedTimer, savedAlarm])
        precondition(restored.timers[0].status == .missed && restored.timers[0].label == "Tea")
        precondition(restored.timers[1].kind == .alarm && restored.timers[1].status == .running)
        restored.dismiss(savedTimer)
        precondition(restored.timers.first?.id == savedAlarm)
        restored.cancel(savedAlarm)
        restored.stop()
        let empty = LiveTimerStore(defaults: defaults, clock: { instant }, playSound: {}, stopSound: {})
        precondition(empty.timers.isEmpty)
        empty.stop()
        store.playSoundWhenTimeIsUp = false
        precondition(!LiveTimerStore(defaults: defaults, playSound: {}, stopSound: {}).playSoundWhenTimeIsUp)
        store.stop()
        print("PASS parser, alarms, ordering, ringing, dismissal removal, persistence, missed-on-reload, preferences")
    }
}
