// notchcast-sources: Tinycast/Features/Battery/Model/*.swift Tinycast/Features/Battery/Service/*.swift
// notchcast-kit: root
import Foundation

@main
struct BatteryCoreTests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }
        let now = Date(timeIntervalSince1970: 1000)
        let policy = ChargePolicy(enabled: true)
        check(policy.decide(percent: 90, charging: true, connected: true) == .init(charging: false),
              "above limit pauses charging with adapter connected")
        check(!policy.decide(percent: 80, charging: false, connected: true).charging, "hold at limit")
        check(!policy.decide(percent: 75, charging: false, connected: true).charging, "margin equality")
        check(policy.decide(percent: 74, charging: false, connected: true).charging, "resume below margin")
        check(policy.decide(percent: nil, charging: false, connected: true) == .release, "missing battery")
        var heat = HeatProtection()
        check(heat.paused(enabled: true, celsius: 35, now: now), "hot boundary")
        check(heat.paused(enabled: true, celsius: nil, now: now.addingTimeInterval(299)), "missing holds")
        check(!heat.paused(enabled: true, celsius: 30, now: now.addingTimeInterval(300)), "cooldown boundary")
        var session = CalibrationSession()
        session.start()
        for percent in [100, 10, 100, 80] {
            session.advance(percent: percent, limit: 80, connected: true, now: now)
        }
        check(session.step == nil && session.completedAt == now, "four stages finish")
        session.start()
        session.advance(percent: 100, limit: 80, connected: true, now: now)
        check(session.decision == .init(charging: false),
              "manual calibration drain keeps the adapter connected")
        session.advance(percent: 10, limit: 80, connected: false, now: now)
        check(session.step == .drainToLow, "manual drain waits for reconnection")
        session.advance(percent: 10, limit: 80, connected: true, now: now)
        check(session.step == .chargeToFullAgain && session.decision == .release,
              "reconnecting after manual drain resumes charging")
        session.cancel()
        session.start()
        let saved = try JSONEncoder().encode(session)
        check(try JSONDecoder().decode(CalibrationSession.self, from: saved) == session, "persist roundtrip")
        var engine = ChargeEngine()
        engine.calibration.start()
        check(engine.evaluate(policy: policy, percent: 90, charging: false, connected: true,
                              celsius: 20, now: now).charging, "calibration overrides limit")
        engine.calibration.cancel()
        engine.calibration.start()
        for percent in [100, 10, 100, 90] {
            _ = engine.evaluate(policy: ChargePolicy(enabled: true, limit: 100), percent: percent,
                charging: false, connected: true, celsius: 20, now: now, calibrationLimit: 80)
        }
        check(engine.calibration.step == .returnToLimit, "calibration respects saved limit with Sailing off")
        engine.calibration.cancel()
        let held = engine.evaluate(policy: policy, percent: 95, charging: true, connected: true,
                                   celsius: 20, now: now)
        check(!held.charging, "above limit pauses charging")
        check(engine.evaluate(policy: policy, percent: nil, charging: true, connected: true,
                              celsius: nil, now: now) == held, "missing reading holds state")
        check(engine.evaluate(policy: policy, percent: 95, charging: true, connected: false,
                              celsius: 20, now: now) == held, "unplugging holds state")
        var awake = KeepAwakePolicy(enabled: true)
        check(awake.assertionTypes == ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"],
              "keep awake holds both system and display")
        check(awake.evaluate(now: now, onBattery: true, percent: 20) == .batteryFloor,
              "battery floor boundary")
        awake.until = now
        check(awake.evaluate(now: now, onBattery: false, percent: nil) == .expired, "deadline")
        check(LidClosedPolicy.plan(enabled: true, helperReady: true, keepAwakeHolding: false) == .batterySleepOn,
              "lid follows actual hold")
        var calls: [RootContract.Command] = []
        let service = ChargePlanService()
        try service.apply(.init(charging: false)) { calls.append($0) }
        check(calls == [.batteryAdapterOn, .batteryChargingOff], "every plan restores adapter power")
        enum Injected: Error { case failure }
        var released: [UInt32] = []
        do {
            _ = try KeepAwakePlanService().acquire(types: awake.assertionTypes, create: {
                if $0 == "PreventUserIdleDisplaySleep" { throw Injected.failure }
                return 7
            }, release: { released.append($0) })
        } catch Injected.failure {}
        check(released == [7], "partial assertion failure releases acquired assertion")
        print("PASS: \(count) battery core checks")
    }
}
