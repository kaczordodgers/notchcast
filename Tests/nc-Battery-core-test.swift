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
        var policy = ChargePolicy(enabled: true)
        check(!policy.decide(percent: 90, charging: true, connected: true).adapter, "drain above limit")
        check(policy.decide(percent: 80, charging: false, connected: true).adapter, "restore at limit")
        policy.drain = false
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
        let saved = try JSONEncoder().encode(session)
        check(try JSONDecoder().decode(CalibrationSession.self, from: saved) == session, "persist roundtrip")
        var engine = ChargeEngine()
        engine.calibration.start()
        check(engine.evaluate(policy: policy, percent: 90, charging: false, connected: true,
                              celsius: 20, now: now).charging, "calibration overrides limit")
        var awake = KeepAwakePolicy(enabled: true)
        check(awake.evaluate(now: now, onBattery: true, percent: 20, locked: false) == .batteryFloor,
              "battery floor boundary")
        awake.until = now
        check(awake.evaluate(now: now, onBattery: false, percent: nil, locked: false) == .expired, "deadline")
        check(LidClosedPolicy.plan(enabled: true, helperReady: true, keepAwakeHolding: false) == .sleepOn,
              "lid follows actual hold")
        check(BatteryRootVerbs.sleepOn.command == ["/usr/bin/pmset", "-a", "disablesleep", "0"], "restore command")
        check(BatteryRootVerbs.chargingOff.writes(modern: true).first?.bytes == [1, 0, 0, 0], "SMC plan")
        var calls: [BatteryRootVerbs] = []
        let service = ChargePlanService()
        do {
            try service.apply(.init(charging: false, adapter: false), watchdogReady: false) { calls.append($0) }
            fatalError("unguarded drain")
        } catch ChargePlanService.Failure.watchdogRequired {}
        check(calls.isEmpty, "watchdog required before mutation")
        enum Injected: Error { case failure }
        do {
            try service.apply(.init(charging: false, adapter: false), watchdogReady: true) {
                calls.append($0)
                if $0 == .adapterOff { throw Injected.failure }
            }
        } catch Injected.failure {}
        check(calls == [.chargingOff, .adapterOff, .adapterOn, .chargingOn], "failure restores both")
        var released: [UInt32] = []
        do {
            _ = try KeepAwakePlanService().acquire(types: awake.assertionTypes, create: {
                if $0 == "PreventUserIdleDisplaySleep" { throw Injected.failure }
                return 7
            }, release: { released.append($0) })
        } catch Injected.failure {}
        check(released == [7], "partial assertion failure releases acquired assertion")
        do {
            try BatteryRootPlanService().apply(.chargingOff, modern: true, write: { _, _ in },
                                              read: { _ in [0, 0, 0, 0] })
            fatalError("unverified write")
        } catch BatteryRootPlanService.Failure.readbackMismatch {}
        check(true, "readback mismatch fails")
        print("PASS: \(count) battery core checks")
    }
}
