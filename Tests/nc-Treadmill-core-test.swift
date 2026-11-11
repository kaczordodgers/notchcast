// notchcast-sources: Tinycast/Features/Treadmill/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/Treadmill/Service/*.swift
// notchcast-sources: Tinycast/Features/Treadmill/TreadmillModule.swift
// notchcast-sources: Tinycast/Features/Treadmill/TreadmillCoordinator+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-kit: core
import Foundation

@MainActor final class AppCore {}

@MainActor
final class IslandActivityCenter {
    enum Tone { case neutral }
    static let shared = IslandActivityCenter()
    func showMessage(_ text: String, tone: Tone, dwell: Double, id: String? = nil, symbol: String? = nil) {
        fatalError("Real sink in harness")
    }
}

@MainActor
private final class FakeTreadmillTransport: TreadmillTransport {
    var maintainsConnection = false
    var onReady: (() -> Void)?
    var onFailure: (((any Error)?) -> Void)?
    var onBytes: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var sent: [Data] = []
    var opens = 0
    var closes = 0
    var sentAtClose: [Data] = []
    var failSend = false
    var onOpen: (() -> Void)?

    func open() throws { opens += 1; onOpen?() }
    func send(_ data: Data) throws {
        if failSend { throw TreadmillFailure.unavailable }
        sent.append(data)
    }
    func close() { closes += 1; sentAtClose = sent }
    func emit(_ data: Data) { onBytes?(data) }
}

@MainActor @main
private struct TreadmillTests {
    private static var checks = 0
    private static let now = Date(timeIntervalSince1970: 1_793_793_600)
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private static func expect(_ condition: Bool, _ label: String) {
        checks += 1
        guard condition else { fatalError(label) }
    }

    private static func refuses(_ failure: TreadmillFailure, _ action: () throws -> Void) {
        do {
            try action()
            fatalError("Expected refusal: \(failure)")
        } catch {
            expect(error as? TreadmillFailure == failure, "Wrong refusal: \(error)")
        }
    }

    private static func status(_ phase: UInt8, speed: UInt8 = 40, seconds: Int = 60,
                               meters: Int = 100, steps: Int = 90) -> Data {
        func word(_ value: Int) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
        return TreadmillProtocol.frame([0x51, phase, speed, 0] + word(seconds) + word(meters / 10)
                                      + word(123) + word(steps) + [0, 0, 0, 0])
    }

    private static func short(_ phase: UInt8, _ detail: UInt8 = 0) -> Data {
        TreadmillProtocol.frame([0x51, phase, detail])
    }

    private static func message(_ bytes: Data) -> TreadmillProtocol.Message {
        var stream = TreadmillStream()
        return stream.feed(bytes)[0]
    }

    private static func record(started: Double = now.timeIntervalSince1970, meters: Double = 1000) -> TreadmillRecord {
        TreadmillRecord(started: started, ended: started + 600, seconds: 600, meters: meters,
                         kcal: 40, steps: 1000, averageKmh: 6)
    }

    static func main() async throws {
        try frames()
        try session()
        try summaries()
        try await history()
        try await coordinator()
        rejections()
        registration()
        print("Treadmill: \(checks) checks passed; fake transport only")
    }

    private static func registration() {
        let entries = TreadmillCoordinator.register(AppCore())
        expect(entries.map(\.requires) == [[.treadmillWalk], [.treadmillHistory]], "Walk and history each register an entry")
        expect(entries.allSatisfy { $0.requiresAny.isEmpty && $0.module is TreadmillModule }, "Both entries are switch modules")
        expect(entries.map { ($0.module as? TreadmillModule)?.capability } == [.walk, .history],
               "The walk switch runs the walk capability and the history switch runs history")
    }

    private static func rejections() {
        let pad = UUID()
        var screen = TreadmillPadRejections()
        expect(!screen.discoveryFailed() && !screen.discoveryFailed(), "Two discovery errors keep the pad")
        expect(screen.discoveryFailed(), "Third discovery error in a row rejects")
        screen.reject(pad)
        expect(!screen.allows(pad) && screen.allows(UUID()), "Rejected pad skipped, others allowed")
        expect(!screen.discoveryFailed() && !screen.discoveryFailed(), "Reject resets the error count")
        screen.ready()
        expect(!screen.discoveryFailed() && !screen.discoveryFailed(), "Ready resets the error count")
        screen.stop()
        expect(screen.allows(pad), "Stop clears rejected pads")
        expect(!screen.discoveryFailed() && !screen.discoveryFailed(), "Stop clears the error count")
    }

    private static func frames() throws {
        expect(TreadmillProtocol.queryStatus == Data([2, 0x51, 0x0B, 3]), "Status query")
        expect(TreadmillProtocol.stop == Data([2, 0x53, 3, 0x0C, 3]), "Stop frame")
        expect(TreadmillProtocol.pause == Data([2, 0x53, 0x0A, 7, 3]), "Pause frame")
        expect(TreadmillProtocol.resume == Data([2, 0x53, 9, 6, 3]), "Resume frame")
        let start = try TreadmillProtocol.start(minutes: 10)
        expect(Array(start)[5...6] == [0x58, 2], "Time target little endian")
        let maximum = try TreadmillProtocol.start(minutes: TreadmillProtocol.maximumMinutes)
        expect(Array(maximum)[5...6] == [0xF0, 0xFF], "16-bit time boundary")
        let speed = try TreadmillProtocol.speed(4.25)
        expect(Array(speed)[3] == 43, "Speed rounded to tenths")
        for invalid in [Double.nan, .infinity, -.infinity, 0, 0.99, 6.01, 100] {
            refuses(.invalidSpeed) { _ = try TreadmillProtocol.speed(invalid) }
        }
        for invalid in [-1, 1093, Int.max] {
            refuses(.invalidMinutes) { _ = try TreadmillProtocol.start(minutes: invalid) }
        }
        let full = status(3, seconds: 6015, meters: 4320, steps: 10_019)
        for split in 0...full.count {
            var stream = TreadmillStream()
            let decoded = stream.feed(full.prefix(split)) + stream.feed(full.dropFirst(split))
            expect(decoded.count == 1, "Split frame at \(split)")
            if case .status(let status) = decoded[0] {
                expect(status.sample?.seconds == 6015 && status.sample?.steps == 10_019
                       && status.sample?.meters == 4320, "Counters exceed display widths")
            } else { fatalError("Expected status") }
        }
        var stream = TreadmillStream()
        expect(stream.feed(short(0) + full + short(10)).count == 2, "Joined frames; reject truncated paused counters")
        var damaged = full
        damaged[damaged.count - 2] ^= 1
        expect(stream.feed(damaged).isEmpty, "Bad checksum")
        let junk = Data([2, 0xFF] + Array(repeating: UInt8(255), count: 100))
        expect(stream.feed(junk + short(2, 3)).count == 1, "Recover after garbage")
        expect(stream.feed(TreadmillProtocol.frame([0x51, 254, 0])).isEmpty, "Unknown status")
        expect(stream.feed(Data(repeating: 2, count: 100_000) + full).count == 1, "Bounded junk buffer")
    }

    private static func session() throws {
        var engine = TreadmillSessionEngine()
        _ = try engine.start(speed: 4, minutes: 10, now: now)
        expect(engine.walk == nil, "Start request is not confirmation")
        refuses(.alreadyWalking) { _ = try engine.start(speed: 4, minutes: 0, now: now) }
        let wake = engine.receive(message(short(0)), now: now)
        expect(wake.commands.count == 1, "Wake start retried once")
        expect(engine.receive(message(short(0)), now: now).commands.isEmpty, "No endless start retry")
        _ = engine.receive(message(short(2, 3)), now: now)
        expect(engine.walk?.phase == .countdown, "Countdown confirmation")
        _ = try engine.setSpeed(4.5)
        let running = engine.receive(message(status(3, speed: 10)), now: now.addingTimeInterval(3))
        expect(running.commands == [try TreadmillProtocol.speed(4.5)], "Apply speed after countdown")
        _ = try engine.nudgeSpeed(0.5)
        let secondNudge = try engine.nudgeSpeed(0.5)
        expect(secondNudge == [try TreadmillProtocol.speed(5.5)], "Rapid nudges accumulate")
        _ = try engine.pause()
        _ = engine.receive(message(status(10, speed: 0, seconds: 120)), now: now.addingTimeInterval(120))
        let paused = engine.walk
        refuses(.notRunning) { _ = try engine.setSpeed(4) }
        _ = try engine.resume()
        _ = engine.receive(message(short(2, 3)), now: now.addingTimeInterval(123))
        let resumed = engine.receive(message(status(3, speed: 10, seconds: 120)), now: now.addingTimeInterval(126))
        expect(resumed.commands == [try TreadmillProtocol.speed(5.5)], "Resume restores requested speed")
        expect(engine.walk?.sample.seconds == 120, "Pause does not add wall time")
        var recovered = TreadmillSessionEngine(walk: paused)
        _ = try recovered.resume()
        expect(recovered.receive(message(status(3, speed: 10, seconds: 120)), now: now.addingTimeInterval(126)).commands
               == [try TreadmillProtocol.speed(5.5)], "Recovery preserves paused speed")
        _ = engine.stop(now: now.addingTimeInterval(130))
        expect(engine.walk != nil, "Stop request keeps final counters pending")
        let finished = engine.receive(message(status(1, seconds: 180, meters: 200, steps: 270)),
                                      now: now.addingTimeInterval(180))
        expect(finished.finished.first?.seconds == 180 && finished.finished.first?.meters == 200, "Final counters saved")
        expect(engine.receive(message(short(0)), now: now).finished.isEmpty, "Final record exactly once")
        expect(engine.stop(now: now) == [TreadmillProtocol.stop], "Stop accepts unknown belt state")
        _ = engine.receive(message(short(0)), now: now)
        _ = try engine.start(speed: 4, minutes: 0, now: now)
        expect(engine.checkTimeout(now: now.addingTimeInterval(14)).commands.isEmpty, "No early timeout")
        let timeout = engine.checkTimeout(now: now.addingTimeInterval(15))
        expect(timeout.failure == .timedOut && timeout.commands == [TreadmillProtocol.stop], "Silent start times out with Stop")
        expect(engine.checkTimeout(now: now.addingTimeInterval(16)).commands.isEmpty, "Timeout once")
        refuses(.alreadyWalking) { _ = try engine.start(speed: 4, minutes: 0, now: now) }
        let late = engine.receive(message(status(3)), now: now.addingTimeInterval(17))
        expect(late.commands == [TreadmillProtocol.stop] && engine.walk == nil, "Late running status stopped without adoption")
        _ = engine.receive(message(short(0)), now: now.addingTimeInterval(18))
        _ = engine.receive(message(status(3, seconds: 300)), now: now)
        let replaced = engine.receive(message(status(3, seconds: 1)), now: now.addingTimeInterval(1))
        expect(replaced.finished.count == 1 && engine.walk?.sample.seconds == 1, "Counter reset starts new session")
        let error = engine.receive(message(short(5, 6)), now: now.addingTimeInterval(2))
        expect(error.failure == .padError(6) && error.finished.count == 1, "Pad error ends and saves walk")
    }

    private static func summaries() throws {
        let yesterday = now.addingTimeInterval(-86_400).timeIntervalSince1970
        let records = [record(), record(started: yesterday), record(started: now.timeIntervalSince1970 + 86_400)]
        let summary = TreadmillSummary(records: records, current: nil, now: now, calendar: calendar)
        expect(summary.today.walks == 1 && summary.odometerKm == 2, "Calendar buckets exclude future records")
        expect(summary.today.averageKmh == 6, "Distance weighted average")
        var imported = record()
        imported.imported = true
        let importedSummary = TreadmillSummary(records: [imported], current: nil, now: now, calendar: calendar)
        expect(importedSummary.odometerKm == imported.meters / 1000, "Persisted aggregate contributes distance")
        expect(importedSummary.year.walks == 0 && importedSummary.year.seconds == imported.seconds,
               "Aggregate blocks are not walks")
        expect(importedSummary.monthDays.allSatisfy { $0.totals.seconds == 0 }, "Aggregates stay out of daily chart")
        expect(TreadmillGoal.standard.progress(summary.today) == 1.0 / 6, "Default minutes goal")
        expect(TreadmillGoal(unit: .steps, target: 1000).progress(summary.today) == 1, "Steps goal")
        expect(TreadmillGoal(unit: .kilometers, target: 2).progress(summary.today) == 0.5, "Distance goal")
        var archive = TreadmillArchive()
        archive.lubricatedKm = 400
        expect(archive.lubeDueMark(odometerKm: 599.99) == nil, "Not due before lube mark")
        expect(archive.lubeDueMark(odometerKm: 600) == 600, "Lube due at 200 km boundary")
        archive.lubricatedKm = 650
        expect(archive.lubeDueMark(odometerKm: 799.99) == nil, "Lubricated between marks")
        let invalid = record(meters: -.infinity)
        expect(!invalid.isValid, "Non-finite history rejected")
    }

    @MainActor
    private static func history() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-Treadmill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = TreadmillRepository(directory: root.appending(path: "fork"))
        let store = TreadmillHistoryStore(repository: repository)
        try await store.load()
        expect(store.archive == TreadmillArchive(), "Missing archive starts empty without injected history")
        store.update(current: nil, finished: [record()])
        store.markLubricated(odometerKm: 400)
        var engine = TreadmillSessionEngine()
        _ = engine.receive(message(status(3)), now: now.addingTimeInterval(1000))
        store.update(current: engine.walk, finished: [])
        async let first: Void = store.flush()
        async let second: Void = store.flush()
        try await first
        try await second
        let restored = try await repository.load()
        expect(restored.current == engine.walk, "Concurrent flushes preserve recovery snapshot")
        let end = engine.receive(message(status(1, seconds: 120)), now: now.addingTimeInterval(1120))
        store.update(current: engine.walk, finished: end.finished)
        store.update(current: engine.walk, finished: end.finished)
        expect(store.archive.records.count == 2, "Duplicate finish cannot duplicate history")
        expect(store.takeGoalReached(TreadmillGoal(unit: .steps, target: 1), now: now, calendar: calendar), "Goal event")
        expect(!store.takeGoalReached(.standard, now: now, calendar: calendar), "Goal event once per day")
        try await store.flush()
        let afterFinish = try await repository.load()
        expect(afterFinish.current == nil && afterFinish.records.count == 2, "Finish and clear commit atomically")
        expect(afterFinish.goalAnnouncedDay == calendar.startOfDay(for: now), "Goal announcement survives restart")
        let reopened = TreadmillHistoryStore(repository: repository)
        try await reopened.load()
        expect(reopened.archive.records.count == 2, "Persisted history does not gain records on reload")
        async let concurrent: Void = reopened.flush()
        for index in 1...20 {
            reopened.markLubricated(odometerKm: Double(index))
            await Task.yield()
        }
        try await concurrent
        try await reopened.flush()
        let latest = try await repository.load()
        expect(latest.lubricatedKm == 20, "Changes during a write finish in the latest snapshot")
        let corrupt = root.appending(path: "corrupt")
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        let damaged = Data("{\"records\": [".utf8)
        try damaged.write(to: corrupt.appending(path: "treadmill.json"))
        let badStore = TreadmillHistoryStore(repository: TreadmillRepository(directory: corrupt))
        do { try await badStore.load(); fatalError("Corrupt archive accepted") } catch {}
        expect(!badStore.isLoaded, "Corruption does not initialize an empty replacement")
        expect(try Data(contentsOf: corrupt.appending(path: "treadmill.json")) == damaged, "Corrupt archive preserved")
        let blocked = root.appending(path: "blocked")
        let failedStore = TreadmillHistoryStore(repository: TreadmillRepository(directory: blocked.appending(path: "fork")))
        try await failedStore.load()
        try Data().write(to: blocked)
        do { try await failedStore.flush(); fatalError("Expected write failure") } catch {}
        try FileManager.default.removeItem(at: blocked)
        try await failedStore.flush()
        expect(FileManager.default.fileExists(atPath: blocked.appending(path: "fork/treadmill.json").path), "Failed save retries")
    }

    @MainActor
    private static func coordinator() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-Treadmill-" + UUID().uuidString)
        let domain = "nc-Treadmill-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let preferences = TreadmillPreferences(defaults: defaults)
        expect(preferences.goal == .standard, "60 minutes default")
        try preferences.setGoal(nil)
        expect(TreadmillPreferences(defaults: defaults).goal == nil, "Disabled goal persists")
        try preferences.setGoal(TreadmillGoal(unit: .steps, target: 100))
        expect(TreadmillPreferences(defaults: defaults).goal?.unit == .steps, "Goal preference round trip")
        let transport = FakeTreadmillTransport()
        let store = TreadmillHistoryStore(repository: TreadmillRepository(directory: root))
        let coordinator = TreadmillCoordinator(transport: transport, history: store, preferences: preferences,
                                              clock: { now }, calendar: { calendar })
        refuses(.disabled) { try coordinator.startWalk() }
        try await coordinator.prepare()
        let module = TreadmillModule(coordinator, capability: .walk)
        transport.maintainsConnection = true
        let freshPreferences = NotchcastPreferences(suiteName: domain)
        let modules = NotchcastModuleController([.init(requires: [.treadmillWalk], module: module)],
                                               preferences: freshPreferences)
        modules.run()
        expect(!freshPreferences.isOn(.treadmillWalk) && !coordinator.walkEnabled && transport.opens == 0,
               "Fresh Walking Pad preference is off and module does not open transport")
        transport.maintainsConnection = false
        print("Treadmill safety: fresh switch off; timeout emits Stop; late running rejected; restart waits for idle")
        module.start()
        coordinator.setEnabled(.history, true)
        expect(transport.opens == 0 && transport.sent.isEmpty, "Enabling never opens transport")
        coordinator.setEnabled(.walk, false)
        expect(transport.opens == 0 && transport.sent.isEmpty && coordinator.lastError == nil,
               "Idle disable leaves a phone-started walk alone without connecting")
        coordinator.setEnabled(.walk, true)
        await coordinator.stopForTermination()
        expect(transport.opens == 0 && transport.sent.isEmpty && coordinator.lastError == nil,
               "Idle termination needs no nearby pad")
        coordinator.setEnabled(.walk, true)
        coordinator.setEnabled(.history, true)
        try coordinator.stopWalk()
        expect(transport.opens == 1 && transport.sent == [TreadmillProtocol.stop],
               "Stop connects even with no known walk")
        coordinator.setEnabled(.walk, false)
        expect(transport.sent == [TreadmillProtocol.stop, TreadmillProtocol.stop],
               "Connected idle disable sends Stop")
        coordinator.setEnabled(.walk, true)
        coordinator.disconnect()
        transport.sent = []
        try coordinator.toggleWalk()
        expect(transport.sent == [TreadmillProtocol.queryStatus], "Unknown toggle queries before starting")
        transport.emit(status(3))
        expect(transport.sent == [TreadmillProtocol.queryStatus, TreadmillProtocol.stop],
               "Remote walk toggle stops without START")
        transport.emit(short(0))
        coordinator.disconnect()
        transport.sent = []
        try coordinator.toggleWalk()
        expect(transport.sent == [TreadmillProtocol.queryStatus], "Idle toggle waits for reply")
        transport.emit(short(0))
        expect(transport.sent.last == (try TreadmillProtocol.start(minutes: 0)), "Confirmed idle toggle starts")
        coordinator.disconnect()
        transport.sent = []
        coordinator.setEnabled(.walk, false)
        expect(transport.sent.isEmpty && !coordinator.connected,
               "Disabling disconnected idle state does not send Stop")
        coordinator.setEnabled(.walk, true)
        transport.sent = []
        try coordinator.startWalk()
        expect(transport.sent.count == 1, "Start opens injected transport once")
        coordinator.setEnabled(.walk, false)
        expect(transport.sent.last == TreadmillProtocol.stop && transport.sentAtClose == transport.sent,
               "Disabling a pending start sends Stop before closing")
        coordinator.setEnabled(.walk, true)
        transport.sent = []
        try coordinator.startWalk()
        transport.emit(short(2, 3))
        transport.emit(status(3, steps: 100))
        try coordinator.faster()
        try coordinator.faster()
        expect(transport.sent.last == TreadmillProtocol.frame([0x53, 2, 50, 0]), "Commands accumulate speed")
        let stale = transport.onBytes
        let count = transport.sent.count
        coordinator.setEnabled(.walk, false)
        stale?(status(1, seconds: 500))
        expect(transport.sent.count == count + 1 && transport.sent.last == TreadmillProtocol.stop
               && transport.sentAtClose == transport.sent && coordinator.engine.walk?.sample.seconds == 60,
               "Disable sends Stop and invalidates callbacks")
        refuses(.disabled) { try coordinator.faster() }
        coordinator.setEnabled(.history, false)
        refuses(.disabled) { _ = try coordinator.stats() }
        try await store.flush()
        coordinator.setEnabled(.walk, true)
        transport.failSend = true
        let before = coordinator.engine.requestedSpeed
        refuses(.unavailable) { try coordinator.faster() }
        expect(coordinator.engine.requestedSpeed == before, "Failed send rolls back requested speed")
        transport.failSend = false
        transport.onDisconnect?()
        expect(!coordinator.connected, "Disconnect clears connection")
        let opensBeforeTermination = transport.opens
        await coordinator.stopForTermination()
        expect(transport.opens == opensBeforeTermination + 1 && transport.sent.last == TreadmillProtocol.stop
               && transport.sentAtClose == transport.sent,
               "Termination reconnects a known walk and sends Stop before closing")
        try await store.flush()
        module.stop()
        let reentrantTransport = FakeTreadmillTransport()
        let reentrantStore = TreadmillHistoryStore(repository: TreadmillRepository(directory: root.appending(path: "reentrant")))
        let reentrant = TreadmillCoordinator(transport: reentrantTransport, history: reentrantStore,
                                            preferences: preferences, clock: { now }, calendar: { calendar })
        try await reentrant.prepare()
        reentrant.setEnabled(.walk, true)
        reentrant.setEnabled(.history, true)
        try reentrant.startWalk()
        reentrantTransport.emit(short(2, 3))
        reentrantTransport.emit(status(3, speed: 10, steps: 100))
        await reentrant.stopForTermination()
        let terminated = try await TreadmillRepository(directory: root.appending(path: "reentrant")).load()
        expect(terminated.current?.sample.steps == 100, "Termination flushes the last counters")
        let persistent = FakeTreadmillTransport()
        persistent.maintainsConnection = true
        let reconnecting = TreadmillCoordinator(transport: persistent,
            history: TreadmillHistoryStore(repository: TreadmillRepository(directory: root.appending(path: "reconnect"))),
            preferences: preferences, clock: { now }, calendar: { calendar })
        try await reconnecting.prepare()
        reconnecting.setEnabled(.walk, true)
        expect(persistent.opens == 1 && !reconnecting.connected, "Open waits for transport readiness")
        persistent.onReady?()
        expect(reconnecting.connected && persistent.sent.last == TreadmillProtocol.queryStatus,
               "Ready connects and queries status through the protocol")
        persistent.onFailure?(TreadmillBluetoothFailure.padAbsent)
        persistent.onFailure?(TreadmillBluetoothFailure.padAbsent)
        expect(reconnecting.lastError as? TreadmillBluetoothFailure == .padAbsent,
               "Repeated absence preserves the transport error")
        persistent.onFailure?(nil)
        expect(reconnecting.lastError == nil, "Transport recovery clears its own error")
        persistent.failSend = true
        persistent.onReady?()
        expect(reconnecting.lastError as? TreadmillFailure == .unavailable, "Send failure is reported")
        persistent.onFailure?(nil)
        persistent.onFailure?(TreadmillBluetoothFailure.padAbsent)
        expect(reconnecting.lastError as? TreadmillFailure == .unavailable,
               "Transport recovery and absence preserve unrelated errors")
        persistent.failSend = false
        persistent.emit(status(3, steps: 100))
        let walk = reconnecting.engine.walk
        expect(walk != nil, "Remote walk is tracked")
        persistent.onDisconnect?()
        expect(!reconnecting.connected && reconnecting.engine.walk == walk && persistent.closes == 0,
               "Persistent transport disconnect preserves walk without closing")
        persistent.onReady?()
        persistent.emit(status(3, steps: 120))
        expect(reconnecting.connected && reconnecting.engine.walk?.started == walk?.started
               && reconnecting.engine.walk?.sample.steps == 120, "Reconnect resumes the same walk")
        await reconnecting.stopForTermination()
        var staleNow = now
        let staleTransport = FakeTreadmillTransport()
        let staleStore = TreadmillHistoryStore(repository: TreadmillRepository(directory: root.appending(path: "stale")))
        let silent = TreadmillCoordinator(transport: staleTransport, history: staleStore,
                                         preferences: preferences, clock: { staleNow }, calendar: { calendar })
        try await silent.prepare()
        silent.setEnabled(.walk, true)
        silent.setEnabled(.history, true)
        try silent.startWalk()
        staleTransport.emit(status(3))
        try silent.stopWalk()
        staleNow = now.addingTimeInterval(16)
        staleTransport.sent = []
        try silent.toggleWalk()
        expect(staleTransport.sent == [TreadmillProtocol.queryStatus], "A stale walk's toggle queries instead of stopping")
        staleTransport.emit(short(0))
        expect(staleTransport.sent.last == (try TreadmillProtocol.start(minutes: 0))
               && staleStore.archive.records.count == 1, "Standby after a stale walk records it once and starts")
        await silent.stopForTermination()
        print("Treadmill protocol lifecycle passed: readiness, preserved walk, reconnect resumes counters")
    }
}
