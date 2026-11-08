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
        print("nc-Treadmill-session-timeout: 7 checks passed")
    }
}
