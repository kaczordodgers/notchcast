import Foundation
import Observation
import os

@MainActor @Observable
final class TreadmillCoordinator {
    enum Capability { case walk, history }

    let history: TreadmillHistoryStore
    let preferences: TreadmillPreferences
    private(set) var engine = TreadmillSessionEngine()
    private(set) var walkEnabled = false
    private(set) var historyEnabled = false
    private(set) var connected = false
    private(set) var isReady = false
    private(set) var lastError: (any Error)?
    @ObservationIgnored var agentIndex: AgentActionIndex?
    @ObservationIgnored var onGoalReached: (() -> Void)?
    @ObservationIgnored private let transport: any TreadmillTransport
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let reminders: TreadmillReminders?
    @ObservationIgnored private var stream = TreadmillStream()
    @ObservationIgnored private var togglePending = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loadGeneration = UUID()
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var persistence: Task<Void, Never>?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    private static let logger = Logger(subsystem: NotchcastIdentity.current.bundleID, category: "Treadmill")

    init(transport: any TreadmillTransport, history: TreadmillHistoryStore, preferences: TreadmillPreferences,
         clock: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
         reminders: TreadmillReminders? = nil) {
        self.reminders = reminders
        self.transport = transport
        self.history = history
        self.preferences = preferences
        self.clock = clock
        self.calendar = calendar
        transport.onReady = { [weak self] in
            guard let self, self.walkEnabled else { return }
            self.connected = true
            if self.lastError is TreadmillBluetoothFailure { self.lastError = nil }
            do { try self.transport.send(TreadmillProtocol.queryStatus) } catch { self.report(error) }
        }
        transport.onFailure = { [weak self] error in
            guard let self, self.lastError == nil || self.lastError is TreadmillBluetoothFailure else { return }
            let failure = error as? TreadmillBluetoothFailure
            guard (self.lastError as? TreadmillBluetoothFailure) != failure else { return }
            self.lastError = failure
        }
    }

    isolated deinit {
        loading?.cancel()
        persistence?.cancel()
        timeout?.cancel()
        transport.onBytes = nil
        transport.onDisconnect = nil
        transport.close()
    }

    func setEnabled(_ capability: Capability, _ enabled: Bool) {
        switch capability {
        case .walk:
            if !enabled, walkEnabled, connected || engine.walk != nil || engine.isStarting {
                do { try stopWalk() } catch { report(error) }
            }
            walkEnabled = enabled
            updateAgentRegistration()
            if !enabled { disconnect() }
            if enabled, transport.maintainsConnection {
                do { try connect() } catch { report(error) }
            }
        case .history: historyEnabled = enabled
        }
        guard walkEnabled || historyEnabled else {
            loading?.cancel()
            loading = nil
            loadGeneration = UUID()
            return
        }
        guard loading == nil, !isReady else { return }
        let token = loadGeneration
        loading = Task { [weak self] in
            guard let self else { return }
            defer { if self.loadGeneration == token { self.loading = nil } }
            do {
                try await self.prepare()
            } catch is CancellationError {
                return
            } catch {
                guard self.loadGeneration == token else { return }
                self.report(error)
            }
        }
    }

    func prepare() async throws {
        try await history.load()
        try Task.checkCancellation()
        if engine.walk == nil { engine = TreadmillSessionEngine(walk: history.archive.current) }
        try await history.flush()
        try Task.checkCancellation()
        isReady = true
    }

    func stopForTermination() async {
        setEnabled(.walk, false)
        setEnabled(.history, false)
        do { try await history.flush() } catch { report(error) }
    }

    func startWalk(speed: Double = 4, minutes: Int = 0) throws {
        let now = clock()
        try perform { try $0.start(speed: speed, minutes: minutes, now: now) }
        timeout?.cancel()
        let token = generation
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == token else { return }
            let update = self.engine.checkTimeout(now: self.clock())
            for command in update.commands { try? self.transport.send(command) }
            if let failure = update.failure { self.report(failure) }
        }
    }

    func stopWalk() throws {
        togglePending = false
        try perform { $0.stop(now: clock()) }
    }
    func pauseWalk() throws { try perform { try $0.pause() } }
    func resumeWalk() throws { try perform { try $0.resume() } }
    func setSpeed(_ kmh: Double) throws { try perform { try $0.setSpeed(kmh) } }
    func faster() throws { try perform { try $0.nudgeSpeed(0.5) } }
    func slower() throws { try perform { try $0.nudgeSpeed(-0.5) } }

    func toggleWalk() throws {
        guard walkEnabled else { throw TreadmillFailure.disabled }
        guard isReady else { throw TreadmillFailure.notReady }
        if engine.isStarting || engine.walk != nil && !engine.isStale(now: clock()) { try stopWalk(); return }
        if !connected { try connect() }
        togglePending = true
        do { try transport.send(TreadmillProtocol.queryStatus) } catch {
            togglePending = false
            report(error)
            throw error
        }
    }

    func togglePause() throws {
        if engine.walk?.phase == .paused { try resumeWalk() } else { try pauseWalk() }
    }

    func stats() throws -> TreadmillSummary {
        guard historyEnabled else { throw TreadmillFailure.disabled }
        guard isReady else { throw TreadmillFailure.notReady }
        return history.summary(now: clock(), calendar: calendar())
    }

    func disconnect() {
        togglePending = false
        generation = UUID()
        timeout?.cancel()
        timeout = nil
        transport.onBytes = nil
        transport.onDisconnect = nil
        transport.close()
        connected = false
        stream = TreadmillStream()
        engine = TreadmillSessionEngine(walk: engine.walk)
        if history.isLoaded {
            history.update(current: engine.walk, finished: [])
            persist()
        }
    }

    private func perform(_ action: (inout TreadmillSessionEngine) throws -> [Data]) throws {
        guard walkEnabled else { throw TreadmillFailure.disabled }
        guard isReady else { throw TreadmillFailure.notReady }
        var next = engine
        _ = try action(&next)
        if !connected { try connect() }
        next = engine
        let commands = try action(&next)
        let previous = engine
        engine = next
        do {
            for command in commands { try transport.send(command) }
            lastError = nil
            history.update(current: engine.walk, finished: [])
            persist()
        } catch {
            engine = previous
            report(error)
            throw error
        }
    }

    private func connect() throws {
        let token = generation
        transport.onBytes = { [weak self] data in
            guard let self, self.generation == token, self.walkEnabled else { return }
            self.receive(data)
        }
        transport.onDisconnect = { [weak self] in
            guard let self, self.generation == token else { return }
            if self.transport.maintainsConnection {
                self.connected = false
                self.togglePending = false
                self.stream = TreadmillStream()
                self.engine = TreadmillSessionEngine(walk: self.engine.walk)
            } else { self.disconnect() }
        }
        do {
            try transport.open()
            guard generation == token else { throw TreadmillFailure.unavailable }
            if !transport.maintainsConnection { connected = true }
        } catch {
            disconnect()
            report(error)
            throw error
        }
    }

    private func receive(_ bytes: Data) {
        let token = generation
        for message in stream.feed(bytes) {
            guard generation == token, walkEnabled else { return }
            let previousPhase = engine.walk?.phase
            let update = engine.receive(message, now: clock())
            if let failure = update.failure { report(failure) }
            history.update(current: engine.walk, finished: update.finished)
            let reachedGoal = historyEnabled
                && history.takeGoalReached(preferences.goal, now: clock(), calendar: calendar())
            if reachedGoal {
                onGoalReached?()
            }
            let reminded = historyEnabled && (reminders?.post(history: history, reachedGoal: reachedGoal,
                                                               now: clock(), calendar: calendar()) ?? false)
            persist(force: previousPhase != engine.walk?.phase || !update.finished.isEmpty || reachedGoal || reminded)
            guard generation == token, walkEnabled else { return }
            do {
                for command in update.commands { try transport.send(command) }
                if togglePending, case .status(let status) = message {
                    togglePending = false
                    switch status.phase {
                    case .standby, .ready, .asleep, .ended: try startWalk()
                    default: try stopWalk()
                    }
                }
            } catch {
                report(error)
                disconnect()
                return
            }
        }
    }

    private func persist(force: Bool = true) {
        let now = clock()
        guard force || now.timeIntervalSince(lastCheckpoint) >= 30 else { return }
        lastCheckpoint = now
        guard persistence == nil else { return }
        persistence = Task { [weak self] in
            guard let self else { return }
            defer { self.persistence = nil }
            do { try await self.history.flush() } catch { self.report(error) }
        }
    }

    private func report(_ error: any Error) {
        lastError = error
        Self.logger.error("Treadmill operation failed: \(String(describing: error))")
    }
}
