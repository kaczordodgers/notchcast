import Foundation

struct TreadmillSessionEngine: Sendable {
    struct Update: Sendable {
        var commands: [Data] = []
        var finished: [TreadmillRecord] = []
        var failure: TreadmillFailure?
    }

    private(set) var walk: TreadmillWalk?
    private(set) var requestedSpeed: Double?
    private var movingSpeed: Double?
    private var startFrame: Data?
    private var startDeadline: Date?
    private var startsSent = 0
    private var restoreSpeed = false
    private var silentStopDeadline: Date?
    private static let silenceTimeout: TimeInterval = 15

    var isStarting: Bool { startFrame != nil }

    init(walk: TreadmillWalk? = nil) {
        self.walk = walk
        movingSpeed = walk?.resumeSpeed ?? walk.flatMap { $0.sample.speed > 0 ? $0.sample.speed : nil }
    }

    mutating func start(speed: Double, minutes: Int, now: Date) throws -> [Data] {
        let silent = silentStopDeadline.map { now >= $0 }
        guard startFrame == nil, silent ?? (walk == nil) else { throw TreadmillFailure.alreadyWalking }
        _ = try TreadmillProtocol.speed(speed)
        let frame = try TreadmillProtocol.start(minutes: minutes)
        requestedSpeed = (speed * 10).rounded() / 10
        restoreSpeed = true
        startFrame = frame
        startDeadline = now.addingTimeInterval(Self.silenceTimeout)
        startsSent = 1
        return [frame]
    }

    mutating func pause() throws -> [Data] {
        guard let walk else { throw TreadmillFailure.noWalk }
        guard walk.phase == .running else { throw TreadmillFailure.notRunning }
        movingSpeed = requestedSpeed ?? movingSpeed ?? TreadmillProtocol.speedRange.lowerBound
        self.walk?.resumeSpeed = movingSpeed
        return [TreadmillProtocol.pause]
    }

    mutating func resume() throws -> [Data] {
        guard walk?.phase == .paused else { throw TreadmillFailure.notPaused }
        requestedSpeed = movingSpeed ?? TreadmillProtocol.speedRange.lowerBound
        restoreSpeed = true
        return [TreadmillProtocol.resume]
    }

    mutating func stop(now: Date) -> [Data] {
        silentStopDeadline = now.addingTimeInterval(Self.silenceTimeout)
        startFrame = nil
        startDeadline = nil
        restoreSpeed = false
        return [TreadmillProtocol.stop]
    }

    mutating func setSpeed(_ speed: Double) throws -> [Data] {
        guard let walk else { throw TreadmillFailure.noWalk }
        guard silentStopDeadline == nil, walk.phase == .running || walk.phase == .countdown else {
            throw TreadmillFailure.notRunning
        }
        let frame = try TreadmillProtocol.speed(speed)
        requestedSpeed = (speed * 10).rounded() / 10
        if walk.phase == .countdown {
            restoreSpeed = true
            return []
        }
        return [frame]
    }

    mutating func nudgeSpeed(_ delta: Double) throws -> [Data] {
        guard delta.isFinite else { throw TreadmillFailure.invalidSpeed }
        let current = requestedSpeed ?? walk?.sample.speed ?? TreadmillProtocol.speedRange.lowerBound
        let speed = min(max(current + delta, TreadmillProtocol.speedRange.lowerBound), TreadmillProtocol.speedRange.upperBound)
        return try setSpeed(speed)
    }

    mutating func checkTimeout(now: Date) -> Update {
        guard let startDeadline, now >= startDeadline else { return Update() }
        clearPending()
        silentStopDeadline = now.addingTimeInterval(Self.silenceTimeout)
        return Update(commands: [TreadmillProtocol.stop], failure: .timedOut)
    }

    mutating func receive(_ message: TreadmillProtocol.Message, now: Date) -> Update {
        guard case .status(let status) = message else { return checkTimeout(now: now) }
        let moving = switch status.phase {
        case .countdown, .running, .slowing, .paused: true
        case .standby, .ready, .asleep, .ended, .error: false
        }
        var stale = Update()
        if moving, let silentStopDeadline, now >= silentStopDeadline {
            if let walk, walk.phase == .paused && status.phase == .countdown
                || status.sample.map({ $0.seconds >= walk.sample.seconds }) == true {
                self.silentStopDeadline = nil
            } else {
                endWalk(into: &stale)
            }
        }
        var update = checkTimeout(now: now)
        update.finished = stale.finished
        if !moving {
            silentStopDeadline = nil
        } else if silentStopDeadline != nil {
            silentStopDeadline = now.addingTimeInterval(Self.silenceTimeout)
            if walk == nil {
                if update.commands.isEmpty { update.commands.append(TreadmillProtocol.stop) }
                return update
            }
        }
        switch status.phase {
        case .countdown:
            if walk == nil { walk = TreadmillWalk(started: now, updated: now, phase: .countdown) }
            walk?.phase = .countdown
            startFrame = nil
            startDeadline = nil
        case .running, .slowing, .paused:
            guard let sample = status.sample else { return update }
            if let old = walk, old.sample.seconds > sample.seconds + 30 { finish(into: &update) }
            if walk == nil {
                walk = TreadmillWalk(started: now.addingTimeInterval(-Double(sample.seconds)),
                                     updated: now, phase: status.phase)
            }
            let wasPaused = walk?.phase == .paused
            walk?.sample = sample
            walk?.updated = now
            walk?.phase = status.phase
            startFrame = nil
            startDeadline = nil
            if status.phase == .paused, !wasPaused {
                movingSpeed = requestedSpeed ?? movingSpeed
                requestedSpeed = movingSpeed
                walk?.resumeSpeed = movingSpeed
            }
            if status.phase == .running {
                if restoreSpeed, let speed = requestedSpeed {
                    restoreSpeed = false
                    if abs(speed - sample.speed) > 0.05,
                       let frame = try? TreadmillProtocol.speed(speed) { update.commands.append(frame) }
                }
                movingSpeed = requestedSpeed ?? (TreadmillProtocol.speedRange.contains(sample.speed) ? sample.speed : movingSpeed)
                walk?.resumeSpeed = movingSpeed
                if let requestedSpeed, abs(requestedSpeed - sample.speed) < 0.05 { self.requestedSpeed = nil }
            }
        case .ended:
            if let sample = status.sample { walk?.sample = sample; walk?.updated = now }
            finish(into: &update)
        case .standby, .ready, .asleep, .error:
            if status.phase == .error { update.failure = .padError(status.detail) }
            if walk != nil { finish(into: &update) }
            if status.phase == .standby || status.phase == .ready, let startFrame, startsSent < 2 {
                startsSent += 1
                update.commands.append(startFrame)
            }
            if status.phase == .error { clearPending() }
        }
        return update
    }

    private mutating func finish(into update: inout Update) {
        let restarting = walk != nil && startFrame != nil
        endWalk(into: &update)
        if !restarting { clearPending() }
    }

    private mutating func endWalk(into update: inout Update) {
        if let walk, walk.sample.seconds > 0 || walk.sample.meters > 0 || walk.sample.steps > 0 {
            update.finished.append(walk.record)
        }
        walk = nil
        movingSpeed = nil
        silentStopDeadline = nil
    }

    private mutating func clearPending() {
        startFrame = nil
        startDeadline = nil
        requestedSpeed = nil
        restoreSpeed = false
        startsSent = 0
    }
}
