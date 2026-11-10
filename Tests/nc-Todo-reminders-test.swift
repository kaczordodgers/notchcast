// notchcast-sources: Tinycast/Features/Todo/Model/*.swift Tinycast/Features/Todo/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/AgentGrantStore.swift
// notchcast-sources: Tinycast/Features/AgentConfirm/Model/*.swift
// notchcast-kit: platform
import AppKit

@main
@MainActor
struct TodoReminderTests {
    @MainActor
    final class Clock {
        var now: Date
        var calendar: Calendar
        var reminders: [TodoReminder] = []
        var existing: Set<String> = ["task", "other"]
        var completed: Set<String> = []
        var due: [String: (due: Date, hasTime: Bool)] = [:]
        var snoozes: [UUID: Date] = [:]
        var fires: [TodoReminderFire] = []
        var checkpoints: [TodoReminderState] = []
        var onCheckpoint: (() -> Void)?

        init(now: Date) {
            self.now = now
            calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        }

        func schedule(at date: Date? = nil) -> TodoReminderSchedule {
            TodoReminderSchedule(
                reminders: reminders, taskExists: { self.existing.contains($0) },
                dueDate: { self.due[$0] }, completedTaskIDs: completed, snoozes: snoozes,
                now: date ?? now, calendar: calendar
            )
        }

        func timer(state: TodoReminderState = TodoReminderState(), center: NotificationCenter,
                   workspace: NotificationCenter) -> TodoReminderTimer {
            TodoReminderTimer(
                state: state, now: { self.now }, notificationCenter: center,
                workspaceNotificationCenter: workspace, schedule: { self.schedule(at: $0) },
                onStateChange: {
                    self.checkpoints.append($0)
                    self.onCheckpoint?()
                },
                onFire: {
                    precondition(self.checkpoints.last?.lastCheck == $0.checkedAt)
                    self.fires.append($0)
                }
            )
        }
    }

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    static func reminder(_ kind: TodoReminder.Kind, task: String = "task") -> TodoReminder {
        TodoReminder(id: UUID(), taskID: task, kind: kind)
    }

    static func main() async throws {
        testSchedule()
        testSnoozes()
        testCatchUp()
        testDST()
        try testPersistence()
        await testTimer()
        await testTimerRearmAndTeardown()
        await testTimerExpiration()
        print("PASS: reminder schedule, catch-up, snooze, DST, persistence and timer notifications")
    }

    static func testSchedule() {
        let clock = Clock(now: date("2030-01-01T08:00:00Z"))
        let later = reminder(.absolute(clock.now.addingTimeInterval(600)))
        let sooner = reminder(.absolute(clock.now.addingTimeInterval(300)))
        clock.reminders = [later, sooner]
        precondition(clock.schedule().nextFireDate() == sooner.kind.absoluteDate)
        precondition(clock.schedule().remindersDue(at: clock.now).isEmpty)
        precondition(clock.schedule().remindersDue(at: clock.now.addingTimeInterval(300)).map(\.reminder.id) == [sooner.id])
        let relative = reminder(.relative(minutesBeforeDue: 15))
        clock.reminders = [relative]
        clock.due["task"] = (clock.now.addingTimeInterval(3600), true)
        precondition(clock.schedule().nextFireDate() == clock.now.addingTimeInterval(45 * 60))
        clock.due["task"] = (clock.now.addingTimeInterval(7200), true)
        precondition(clock.schedule().nextFireDate() == clock.now.addingTimeInterval(105 * 60))
        clock.completed = ["task"]
        precondition(clock.schedule().nextFireDate() == nil)
        clock.reminders = [sooner]
        precondition(clock.schedule().entries.isEmpty)
        clock.completed = []
        clock.existing = []
        precondition(clock.schedule().entries.isEmpty)
        clock.reminders = [relative]
        precondition(clock.schedule().entries.isEmpty)
        clock.existing = ["task"]
        clock.due = [:]
        precondition(clock.schedule().entries.isEmpty)
        clock.reminders = [sooner]
        precondition(clock.schedule().entries.count == 1, "Absolute reminders support undated tasks")
        clock.reminders = [reminder(.relative(minutesBeforeDue: -1))]
        clock.due["task"] = (clock.now.addingTimeInterval(3600), true)
        precondition(clock.schedule().entries.isEmpty)
        clock.reminders = [sooner, sooner]
        precondition(clock.schedule().entries.count == 1)
        let tie = reminder(sooner.kind)
        clock.reminders = [tie, sooner]
        precondition(clock.schedule().entries.map(\.reminder.id.uuidString) == [tie.id.uuidString, sooner.id.uuidString].sorted())
        print("PASS: next fire, relative retime, completed/deleted silence, undated tasks and input edges")
    }

    static func testSnoozes() {
        let clock = Clock(now: date("2030-01-01T08:00:00Z"))
        let item = reminder(.absolute(clock.now))
        clock.reminders = [item]
        var state = TodoReminderState()
        precondition(state.check(clock.schedule()).due.count == 1)
        for (option, minutes) in [(TodoReminder.Snooze.fiveMinutes, 5), (.fifteenMinutes, 15), (.oneHour, 60)] {
            let snooze = option.fireDate(now: clock.now, calendar: clock.calendar)!
            precondition(snooze == clock.now.addingTimeInterval(Double(minutes * 60)))
            clock.snoozes[item.id] = snooze
            precondition(state.check(clock.schedule()).isEmpty)
            precondition(clock.schedule().nextFireDate(excluding: state.firedIDs) == snooze)
            clock.now = snooze
            precondition(state.check(clock.schedule()).due.map(\.reminder.id) == [item.id])
            precondition(state.check(clock.schedule()).isEmpty)
            clock.snoozes = [:]
            precondition(state.check(clock.schedule()).isEmpty)
        }
        let tomorrow = TodoReminder.Snooze.tomorrowMorning.fireDate(now: clock.now, calendar: clock.calendar)
        precondition(tomorrow == date("2030-01-02T08:00:00Z"))
        clock.snoozes[item.id] = tomorrow
        precondition(state.check(clock.schedule()).isEmpty)
        clock.now = tomorrow!
        precondition(state.check(clock.schedule()).due.count == 1)
        clock.snoozes = [:]
        precondition(state.check(clock.schedule()).isEmpty)
        clock.completed = ["task"]
        clock.snoozes[item.id] = clock.now
        precondition(state.check(clock.schedule()).isEmpty, "Snoozing cannot bypass completion")
        clock.completed = []
        clock.existing = []
        precondition(state.check(clock.schedule()).isEmpty, "Snoozing cannot resurrect a deleted task")
        print("PASS: 5/15/60 minute and tomorrow snoozes override once")
    }

    static func testCatchUp() {
        let clock = Clock(now: date("2030-01-02T08:00:00Z"))
        let oldest = reminder(.absolute(clock.now.addingTimeInterval(-600)))
        let newest = reminder(.absolute(clock.now.addingTimeInterval(-300)))
        clock.reminders = [newest, oldest]
        var state = TodoReminderState(lastCheck: clock.now.addingTimeInterval(-3600))
        let fire = state.check(clock.schedule())
        precondition(fire.due.map(\.reminder.id) == [oldest.id, newest.id])
        precondition(state.check(clock.schedule()).isEmpty)
        let highWater = clock.now
        clock.now = clock.now.addingTimeInterval(-7200)
        precondition(state.check(clock.schedule()).isEmpty)
        precondition(state.lastCheck == highWater)
        let added = reminder(.absolute(clock.now))
        clock.reminders.append(added)
        precondition(state.check(clock.schedule()).due.map(\.reminder.id) == [added.id])
        clock.now = highWater
        precondition(state.check(clock.schedule()).isEmpty)
        let expired = reminder(.absolute(clock.now.addingTimeInterval(-86401)))
        let boundary = reminder(.absolute(clock.now.addingTimeInterval(-86400)))
        clock.reminders = [boundary, expired]
        state = TodoReminderState()
        let batch = state.check(clock.schedule())
        precondition(batch.due.map(\.reminder.id) == [boundary.id])
        precondition(batch.missed.map(\.reminder.id) == [expired.id])
        precondition(state.check(clock.schedule()).isEmpty)
        let relative = reminder(.relative(minutesBeforeDue: 0))
        clock.reminders = [relative]
        clock.due["task"] = (clock.now.addingTimeInterval(60), true)
        precondition(state.check(clock.schedule()).isEmpty)
        clock.due["task"] = (clock.now.addingTimeInterval(-60), true)
        precondition(state.check(clock.schedule()).due.map(\.reminder.id) == [relative.id])
        clock.due["task"] = (clock.now.addingTimeInterval(60), true)
        clock.now = clock.now.addingTimeInterval(120)
        precondition(state.check(clock.schedule()).due.count == 1)
        precondition(state.check(clock.schedule()).isEmpty)
        precondition(clock.schedule().nextFireDate(excluding: state.firedIDs) == nil)
        let recurring = reminder(.relative(minutesBeforeDue: 30))
        clock.reminders = [recurring]
        clock.now = date("2026-11-03T11:31:00Z")
        clock.due["task"] = (date("2026-11-03T12:00:00Z"), true)
        var recurringState = TodoReminderState()
        precondition(recurringState.check(clock.schedule()).due.count == 1)
        let schedule = TodoRecurrenceRule.Schedule(unit: .day)!
        clock.due["task"] = (TodoRecurrence.nextDue(.every(schedule), currentDue: clock.due["task"]!.due,
            hasTime: true, completedAt: clock.now, calendar: clock.calendar), true)
        precondition(clock.schedule().nextFireDate(excluding: recurringState.firedIDs) != nil)
        clock.now = date("2026-11-04T11:31:00Z")
        precondition(recurringState.check(clock.schedule()).due.count == 1)
        precondition(recurringState.check(clock.schedule()).isEmpty)
        let absoluteID = UUID()
        clock.reminders = [TodoReminder(id: absoluteID, taskID: "task", kind: .absolute(clock.now))]
        precondition(recurringState.check(clock.schedule()).due.count == 1)
        clock.now = clock.now.addingTimeInterval(600)
        clock.reminders = [TodoReminder(id: absoluteID, taskID: "task", kind: .absolute(clock.now))]
        precondition(recurringState.check(clock.schedule()).due.count == 1)
        precondition(recurringState.check(clock.schedule()).isEmpty)
        print("PASS: sleep batches oldest first, backward clock, late edits, one-shot retime and cutoff")
    }

    static func testDST() {
        let clock = Clock(now: date("2030-03-30T08:00:00Z"))
        let spring = TodoReminder.Snooze.tomorrowMorning.fireDate(now: clock.now, calendar: clock.calendar)!
        precondition(spring == date("2030-03-31T07:00:00Z"))
        precondition(spring.timeIntervalSince(clock.now) == 23 * 3600)
        clock.now = date("2030-10-26T07:00:00Z")
        let autumn = TodoReminder.Snooze.tomorrowMorning.fireDate(now: clock.now, calendar: clock.calendar)!
        precondition(autumn == date("2030-10-27T08:00:00Z"))
        precondition(autumn.timeIntervalSince(clock.now) == 25 * 3600)
        let relative = reminder(.relative(minutesBeforeDue: 15))
        clock.reminders = [relative]
        clock.due["task"] = (date("2030-03-30T23:00:00Z"), false)
        precondition(clock.schedule().entries.first?.fireDate == date("2030-03-31T06:45:00Z"))
        clock.due["task"] = (date("2030-10-26T22:00:00Z"), false)
        precondition(clock.schedule().entries.first?.fireDate == date("2030-10-27T07:45:00Z"))
        clock.due["task"] = (date("2030-03-31T01:30:00Z"), true)
        clock.reminders = [reminder(.relative(minutesBeforeDue: 60))]
        precondition(clock.schedule().entries.first?.fireDate == date("2030-03-31T00:30:00Z"))
        clock.due["task"] = (date("2030-10-27T01:30:00Z"), true)
        precondition(clock.schedule().entries.first?.fireDate == date("2030-10-27T00:30:00Z"))
        print("PASS: Warsaw spring/fall DST, all-day 09:00 and elapsed relative offsets")
    }

    static func testPersistence() throws {
        let clock = Clock(now: date("2030-01-01T08:00:00Z"))
        clock.reminders = [reminder(.absolute(clock.now)), reminder(.relative(minutesBeforeDue: 5))]
        clock.due["task"] = (clock.now, true)
        var original = TodoReminderState()
        _ = original.check(clock.schedule())
        let restored = try JSONDecoder().decode(TodoReminderState.self, from: JSONEncoder().encode(original))
        precondition(restored == original)
        var launch = restored
        precondition(launch.check(clock.schedule()).isEmpty)
        let reminders = try JSONDecoder().decode([TodoReminder].self, from: JSONEncoder().encode(clock.reminders))
        precondition(reminders == clock.reminders)
        let empty = try JSONDecoder().decode(TodoReminderState.self, from: JSONEncoder().encode(TodoReminderState()))
        precondition(empty == TodoReminderState())
        print("PASS: Codable state/reminder round-trip and launch deduplication")
    }

    static func post(_ name: Notification.Name, center: NotificationCenter, clock: Clock) async {
        await withCheckedContinuation { continuation in
            clock.onCheckpoint = {
                clock.onCheckpoint = nil
                continuation.resume()
            }
            center.post(name: name, object: nil)
        }
    }

    static func testTimer() async {
        let clock = Clock(now: date("2030-01-01T08:00:00Z"))
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        let first = reminder(.absolute(clock.now.addingTimeInterval(300)))
        let second = reminder(.absolute(clock.now.addingTimeInterval(600)))
        clock.reminders = [second, first]
        let timer = clock.timer(center: center, workspace: workspace)
        timer.start()
        timer.start()
        precondition(clock.checkpoints.count == 1 && timer.nextFireDate == first.kind.absoluteDate)
        clock.now = clock.now.addingTimeInterval(900)
        await post(NSWorkspace.didWakeNotification, center: workspace, clock: clock)
        precondition(clock.fires.count == 1)
        precondition(clock.fires[0].due.map(\.reminder.id) == [first.id, second.id])
        precondition(timer.nextFireDate == nil)
        clock.now = clock.now.addingTimeInterval(-1200)
        await post(.NSSystemClockDidChange, center: center, clock: clock)
        precondition(clock.fires.count == 1)
        clock.now = clock.now.addingTimeInterval(1800)
        await post(.NSSystemClockDidChange, center: center, clock: clock)
        precondition(clock.fires.count == 1)
        let relative = reminder(.relative(minutesBeforeDue: 0))
        clock.reminders = [relative]
        clock.due["task"] = (date("2030-01-01T00:00:00Z"), false)
        timer.check()
        precondition(clock.fires.count == 2, "09:00 Warsaw is past at the fake clock")
        let next = reminder(.relative(minutesBeforeDue: 0))
        clock.reminders = [next]
        clock.due["task"] = (date("2030-01-02T00:00:00Z"), false)
        timer.check()
        precondition(timer.nextFireDate == date("2030-01-02T08:00:00Z"))
        clock.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        await post(.NSSystemTimeZoneDidChange, center: center, clock: clock)
        precondition(timer.nextFireDate == date("2030-01-02T09:00:00Z"))
        clock.due["task"] = (date("2030-01-02T10:00:00Z"), true)
        timer.check()
        precondition(timer.nextFireDate == date("2030-01-02T10:00:00Z"))
        timer.stop()
        precondition(timer.nextFireDate == nil)
        print("PASS: timer launch/wake/clock/time-zone checks and rearming after edits")
    }

    static func testTimerRearmAndTeardown() async {
        let clock = Clock(now: date("2030-01-01T08:00:00Z"))
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        let item = reminder(.absolute(clock.now))
        clock.reminders = [item]
        var timer: TodoReminderTimer? = clock.timer(center: center, workspace: workspace)
        weak let weakTimer = timer
        timer?.start()
        precondition(clock.fires.count == 1)
        clock.snoozes[item.id] = clock.now.addingTimeInterval(300)
        timer?.rearm(item.id)
        precondition(timer?.nextFireDate == clock.now.addingTimeInterval(300))
        clock.now = clock.now.addingTimeInterval(300)
        await post(NSWorkspace.didWakeNotification, center: workspace, clock: clock)
        precondition(clock.fires.count == 2)
        center.post(name: .NSSystemClockDidChange, object: nil)
        timer?.stop()
        timer?.start()
        let count = clock.checkpoints.count
        for _ in 0..<20 { await Task.yield() }
        precondition(clock.checkpoints.count == count, "Queued old-session checks must not run")
        timer?.stop()
        center.post(name: .NSSystemClockDidChange, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        precondition(clock.checkpoints.count == count)
        timer = nil
        precondition(weakTimer == nil)
        let restored = clock.timer(state: clock.checkpoints.last!, center: center, workspace: workspace)
        restored.start()
        precondition(clock.fires.count == 2)
        restored.stop()
        print("PASS: timer snooze, restored launch, stop/restart race and deallocation")
    }

    static func testTimerExpiration() async {
        let clock = Clock(now: date("2030-01-01T08:00:00Z"))
        let first = reminder(.absolute(clock.now.addingTimeInterval(300)))
        let second = reminder(.absolute(clock.now.addingTimeInterval(600)))
        clock.reminders = [second, first]
        var timers: [Timer] = []
        var intervals: [TimeInterval] = []
        let timer = TodoReminderTimer(
            state: TodoReminderState(), now: { clock.now }, notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(), schedule: { clock.schedule(at: $0) },
            makeTimer: { interval, callback in
                precondition(timers.allSatisfy { !$0.isValid }, "Only one timer can remain armed")
                let new = Timer(timeInterval: interval, repeats: false, block: callback)
                timers.append(new)
                intervals.append(interval)
                return new
            },
            onStateChange: { clock.checkpoints.append($0); clock.onCheckpoint?() },
            onFire: { clock.fires.append($0) }
        )
        timer.start()
        precondition(timers.count == 1 && intervals == [300])
        timer.check()
        precondition(!timers[0].isValid && timers[1].isValid)
        clock.now = clock.now.addingTimeInterval(300)
        await withCheckedContinuation { continuation in
            clock.onCheckpoint = {
                clock.onCheckpoint = nil
                continuation.resume()
            }
            timers[1].fire()
        }
        precondition(clock.fires.count == 1 && clock.fires[0].due.map(\.reminder.id) == [first.id])
        precondition(intervals == [300, 300, 300])
        precondition(timer.nextFireDate == second.kind.absoluteDate)
        clock.now = clock.now.addingTimeInterval(300)
        timers[2].fire()
        timer.check()
        let count = clock.checkpoints.count
        for _ in 0..<20 { await Task.yield() }
        precondition(clock.checkpoints.count == count, "Queued invalidated timer must not check again")
        precondition(clock.fires.count == 2 && timer.nextFireDate == nil)
        timer.stop()
        print("PASS: single one-shot timer expiration, replacement and stale callback cancellation")
    }
}

private extension TodoReminder.Kind {
    var absoluteDate: Date? {
        guard case .absolute(let date) = self else { return nil }
        return date
    }
}
