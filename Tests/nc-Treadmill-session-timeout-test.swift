// notchcast-sources: Tinycast/Features/Treadmill/Model/*.swift
import Foundation

@main
private struct TreadmillSessionTimeoutTests {
    static func refusesStart(_ engine: inout TreadmillSessionEngine, at now: Date) -> Bool {
        do { _ = try engine.start(speed: 4, minutes: 0, now: now) } catch TreadmillFailure.alreadyWalking { return true } catch {}
        return false
    }

    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_793_793_600)
        var engine = TreadmillSessionEngine(walk: nil)
        _ = try engine.start(speed: 4, minutes: 0, now: now)

        let timeout = engine.checkTimeout(now: now.addingTimeInterval(15))
        precondition(timeout.failure == .timedOut && timeout.commands == [TreadmillProtocol.stop], "timeout sends Stop")
        precondition(engine.walk == nil && !engine.isStarting, "timeout leaves no walk")
        precondition(refusesStart(&engine, at: now.addingTimeInterval(16)), "a start right after the timeout waits for the pad")

        let running = TreadmillStatus(body: [3, 40, 0, 3, 0, 1, 0, 0, 0, 4, 0, 0, 0, 0, 0])!
        let late = engine.receive(.status(running), now: now.addingTimeInterval(20))
        precondition(late.commands == [TreadmillProtocol.stop] && engine.walk == nil, "late running is stopped")
        precondition(refusesStart(&engine, at: now.addingTimeInterval(34)), "a pad still winding down blocks a start")

        let retry = try engine.start(speed: 4, minutes: 0, now: now.addingTimeInterval(35))
        precondition(retry.count == 1 && engine.isStarting, "a start after the pad stays silent is accepted")
        _ = engine.receive(.status(running), now: now.addingTimeInterval(40))
        precondition(engine.walk?.phase == .running, "the retried start adopts the walk")

        var stopAfterTimeout = TreadmillSessionEngine(walk: nil)
        _ = try stopAfterTimeout.start(speed: 4, minutes: 0, now: now)
        _ = stopAfterTimeout.checkTimeout(now: now.addingTimeInterval(15))
        _ = stopAfterTimeout.stop(now: now.addingTimeInterval(20))
        precondition(refusesStart(&stopAfterTimeout, at: now.addingTimeInterval(34)), "the wait runs from the Stop")
        precondition(!refusesStart(&stopAfterTimeout, at: now.addingTimeInterval(35)), "a Stop after a timeout expires")

        var stopWhileStarting = TreadmillSessionEngine(walk: nil)
        _ = try stopWhileStarting.start(speed: 4, minutes: 0, now: now)
        _ = stopWhileStarting.stop(now: now.addingTimeInterval(10))
        precondition(refusesStart(&stopWhileStarting, at: now.addingTimeInterval(20)), "a stopped start waits from the Stop")
        _ = stopWhileStarting.receive(.status(running), now: now.addingTimeInterval(22))
        precondition(refusesStart(&stopWhileStarting, at: now.addingTimeInterval(30)), "late running pushes the wait")
        precondition(!refusesStart(&stopWhileStarting, at: now.addingTimeInterval(86400)), "a stopped start expires")

        var idle = TreadmillSessionEngine(walk: nil)
        _ = idle.stop(now: now)
        precondition(refusesStart(&idle, at: now.addingTimeInterval(1)), "a start races a belt an idle Stop is slowing")
        let foreign = idle.receive(.status(running), now: now.addingTimeInterval(2))
        precondition(foreign.commands == [TreadmillProtocol.stop] && idle.walk == nil, "an idle Stop re-sends, never adopts")
        let standby = TreadmillStatus(body: [0, 0])!
        _ = idle.receive(.status(standby), now: now.addingTimeInterval(3))
        precondition(!refusesStart(&idle, at: now.addingTimeInterval(3)), "standby after an idle Stop frees a start")

        var silentIdle = TreadmillSessionEngine(walk: nil)
        _ = silentIdle.stop(now: now)
        precondition(!refusesStart(&silentIdle, at: now.addingTimeInterval(15)), "an idle Stop on a silent pad expires")

        var padStart = TreadmillSessionEngine(walk: nil)
        _ = padStart.stop(now: now)
        let adopted = padStart.receive(.status(running), now: now.addingTimeInterval(16))
        precondition(adopted.commands.isEmpty && padStart.walk?.phase == .running, "a walk started after silence is kept")

        var silentWalk = TreadmillSessionEngine(walk: nil)
        _ = silentWalk.receive(.status(running), now: now)
        _ = silentWalk.stop(now: now.addingTimeInterval(60))
        precondition(refusesStart(&silentWalk, at: now.addingTimeInterval(74)), "a stopped walk blocks a start as it winds down")
        precondition(!refusesStart(&silentWalk, at: now.addingTimeInterval(75)), "a stopped walk on a silent pad frees a start")
        let next = silentWalk.receive(.status(standby), now: now.addingTimeInterval(76))
        precondition(next.finished.count == 1 && next.commands.count == 1, "the silent walk is recorded and the start retried")
        print("nc-Treadmill-session-timeout: 21 checks passed")
    }
}
