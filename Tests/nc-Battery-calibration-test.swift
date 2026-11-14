// notchcast-sources: Tinycast/Features/Battery/Model/*.swift Tinycast/Features/Battery/Service/*.swift
// notchcast-kit: core root platform
// notchcast-sources: Tinycast/Features/Battery/Store/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/BatteryReading.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/BatteryService.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/PowerRegistryAccess.swift
// notchcast-sources: Tinycast/Features/Battery/BatteryModule+Registration.swift
import Foundation

@main
@MainActor
struct BatteryCalibrationTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() async {
        var session = CalibrationSession()
        check(!session.liftsChargeLimit(enabled: true, starting: false), "idle session keeps the limit")
        check(session.liftsChargeLimit(enabled: true, starting: true), "a starting session lifts the limit")
        check(!session.liftsChargeLimit(enabled: false, starting: true), "a disabled session keeps it")
        session.start()
        let now = Date(timeIntervalSince1970: 1000)
        var lifts: [Bool] = [session.liftsChargeLimit(enabled: true, starting: false)]
        for percent in [100, 10, 100, 80] {
            session.advance(percent: percent, limit: 80, connected: true, now: now)
            lifts.append(session.liftsChargeLimit(enabled: true, starting: false))
        }
        check(lifts == [true, false, true, false, false], "only the charge-to-100 steps lift: \(lifts)")
        print("PASS: calibration lifts the native limit only while it must reach 100%")
        await moduleCases()
    }

    static func moduleCases() async {
        let suite = "battery-calibration-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var percent = 50
        var currentLimit: Int? = 90
        var calls: [RootContract.Command] = []
        let module = BatteryModule(preferences: preferences, runner: .init(read: {
            BatteryReading.decode(properties: ["CurrentCapacity": percent, "MaxCapacity": 100,
                                               "ExternalConnected": true])
        }, root: { verb in
            calls.append(verb)
            if verb.rawValue.hasPrefix("charge-limit-") {
                currentLimit = Int(verb.rawValue.components(separatedBy: "-").last ?? "")
            }
        }, installed: { true }, version: { RootContract.version }, create: { _ in 1 }, release: { _ in },
           readLimit: { currentLimit }))
        func settle() async {
            for _ in 0..<100 { await Task.yield() }
            await module.waitUntilIdle()
            await module.evaluate(now: .now)
        }
        preferences.batteryChargePercent = 80
        preferences.set(.batteryChargeLimit, true)
        module.start()
        await settle()
        check(currentLimit == 80 && module.nativeLimit == 80, "Charge Limit applies 80%")
        preferences.set(.batteryCalibration, true)
        await settle()
        check(module.calibrationStep == .chargeToFull, "calibration starts at step 1")
        check(currentLimit == nil, "step 1 lifts the native limit, got \(String(describing: currentLimit))")
        check(module.nativeLimit == nil, "Settings shows the lifted limit as off")
        check(preferences.batteryOwnsNativeLimit, "the lift keeps ownership and its undo")
        percent = 100
        await settle()
        check(module.calibrationStep == .drainToLow, "reaching 100% advances past step 1")
        await settle()
        check(currentLimit == 80 && module.nativeLimit == 80, "step 2 restores the user's limit")
        percent = 10
        await settle()
        await settle()
        check(module.calibrationStep == .chargeToFullAgain && currentLimit == nil, "step 3 lifts again")
        percent = 100
        await settle()
        await settle()
        check(module.calibrationStep == .returnToLimit && currentLimit == 80, "step 4 restores the limit")
        percent = 80
        await settle()
        check(!preferences.isOn(.batteryCalibration) && preferences.batteryCalibrationCompletedAt != nil,
              "calibration completes")
        check(currentLimit == 80 && module.nativeLimit == 80, "completion leaves the user's limit")
        print("PASS: calibration with Charge Limit on lifts the limit for steps 1 and 3 and restores it")
        percent = 50
        preferences.set(.batteryCalibration, true)
        await settle()
        check(currentLimit == nil, "a new calibration lifts the limit")
        preferences.set(.batteryCalibration, false)
        await settle()
        check(currentLimit == 80 && module.nativeLimit == 80, "cancelling restores the user's limit")
        print("PASS: cancelling calibration restores the user's limit")
        preferences.set(.batteryCalibration, true)
        await settle()
        check(currentLimit == nil, "lifted before Charge Limit is turned off")
        preferences.set(.batteryChargeLimit, false)
        await settle()
        check(currentLimit == 90 && !preferences.batteryOwnsNativeLimit,
              "turning Charge Limit off mid-lift restores the macOS limit captured before it")
        print("PASS: the journal undo still restores the prior macOS limit after a lift")
        let lifted = calls.filter { $0 == .chargeLimitOff }.count
        await settle()
        check(calls.filter { $0 == .chargeLimitOff }.count == lifted, "no repeated writes once settled")
        module.stop()
        await module.waitUntilIdle()
    }
}
