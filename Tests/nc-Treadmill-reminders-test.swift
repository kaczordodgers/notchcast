// notchcast-sources: Tinycast/Features/Treadmill/Model/*.swift
// notchcast-sources: Tinycast/Features/Treadmill/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/*.swift
import Foundation

@MainActor
private final class ReminderTransport: TreadmillTransport {
    var onBytes: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    func open() throws {}
    func close() {}
    func send(_ data: Data) throws {}
    func emit(_ phase: UInt8 = 3) {
        onBytes?(TreadmillProtocol.frame([0x51, phase, 40, 0, 60, 0, 10, 0, 0, 0, 100, 0, 0, 0, 0, 0]))
    }
}

@MainActor @main
private struct ReminderTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = TreadmillPreferences(defaults: defaults)
        try preferences.setGoal(TreadmillGoal(unit: .steps, target: 100))
        var now = Date(timeIntervalSince1970: 1_793_797_200)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fixedCalendar = calendar
        var messages: [String] = []
        var ids: [String] = []
        var gates = [true, true, true]
        let reminders = TreadmillReminders(enabled: { gates.allSatisfy { $0 } }, present: { text, id in
            messages.append(text)
            ids.append(id)
        })
        let repository = TreadmillRepository(directory: root)
        try await repository.save(TreadmillArchive(importedLegacy: true))
        let store = TreadmillHistoryStore(repository: repository)
        let transport = ReminderTransport()
        let coordinator = TreadmillCoordinator(transport: transport, history: store, preferences: preferences,
            clock: { now }, calendar: { fixedCalendar }, reminders: reminders)
        try await coordinator.prepare()
        coordinator.setEnabled(.history, true)
        coordinator.setEnabled(.walk, true)
        try coordinator.startWalk()
        transport.emit()
        transport.emit()
        precondition(messages == ["Daily walking goal reached"],
                     "Goal once; no lube below 200: \(messages), \(String(describing: coordinator.engine.walk))")
        transport.emit(1)
        now.addTimeInterval(86400)
        coordinator.disconnect()
        try coordinator.startWalk()
        transport.emit()
        transport.emit()
        precondition(messages.count == 2, "Goal again next day")
        func record(_ km: Double, offset: Double) -> TreadmillRecord {
            TreadmillRecord(started: now.timeIntervalSince1970 - offset,
                ended: now.timeIntervalSince1970 - offset + 60, seconds: 60, meters: km * 1000,
                kcal: 0, steps: 0, averageKmh: 4)
        }
        store.update(current: nil, finished: [record(199.9, offset: 1000)])
        transport.emit()
        precondition(messages.last == "Walking pad: time to lubricate the belt (200 km).", "200 km")
        transport.emit()
        precondition(messages.count == 3, "200 once")
        store.update(current: nil, finished: [record(200, offset: 2000)])
        transport.emit()
        precondition(messages.last == "Walking pad: time to lubricate the belt (400 km).", "400 km")
        transport.emit()
        precondition(messages.count == 4, "400 once")
        precondition(ids == ["treadmill.goal", "treadmill.goal", "treadmill.lube", "treadmill.lube"], "Stable ids")
        try await store.flush()
        let reloaded = TreadmillHistoryStore(repository: repository)
        try await reloaded.load(calendar: fixedCalendar)
        precondition(reloaded.archive.lubricatedKm == 400, "Mark persisted")
        _ = reminders.post(history: reloaded, reachedGoal: false, now: now, calendar: fixedCalendar)
        precondition(messages.count == 4, "No repeat after reload")
        precondition(!reloaded.takeGoalReached(preferences.goal, now: now, calendar: fixedCalendar),
                     "Goal day persisted")
        for index in gates.indices {
            gates[index] = false
            reloaded.update(current: nil, finished: [record(200, offset: Double(3000 + index))])
            _ = reminders.post(history: reloaded, reachedGoal: true, now: now, calendar: fixedCalendar)
            precondition(messages.count == 4 && reloaded.archive.lubricatedKm == 400, "Each gate blocks both")
            gates[index] = true
        }
        coordinator.setEnabled(.history, false)
        store.update(current: nil, finished: [record(200, offset: 5000)])
        transport.emit()
        precondition(messages.count == 4, "History capability blocks both")
        await coordinator.stopForTermination()
        print("Treadmill reminders: goal once/day; 200/400 once; below 200 silent; reload durable; all gates silent")
    }
}
