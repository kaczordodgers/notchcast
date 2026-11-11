// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Battery/Model/*.swift Tinycast/Features/Battery/Service/*.swift
// notchcast-kit: core root platform
// notchcast-sources: Tinycast/Features/Battery/Store/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/BatteryReading.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/BatteryService.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/PowerRegistryAccess.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/FanOwnershipJournal.swift
import Foundation

@main
@MainActor
struct OwnershipTests {
    static func settle() async { for _ in 0..<300 { await Task.yield() } }

    static func main() async throws {
        try journalTable()
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL"): \(name)")
            if !value { failures += 1 }
        }
        for scenario in 1...8 {
            let suite = "ownership-test.\(UUID().uuidString)"
            let prefs = NotchcastPreferences(suiteName: suite)
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            var calls: [RootContract.Command] = []
            var limit: Int? = scenario == 3 ? 70 : nil
            var fail = false
            var gate: CheckedContinuation<Void, Never>?
            var gated = false
            if scenario == 1 {
                prefs.batteryRootDirty = true
                prefs.batteryDirtyVerbs = ["battery-charging"]
                prefs.set(.keepAwake, true)
            }
            let module = BatteryModule(preferences: prefs, runner: .init(read: {
                BatteryReading.decode(properties: ["CurrentCapacity": 95, "MaxCapacity": 100,
                    "ExternalConnected": scenario != 4])
            }, root: { verb in
                calls.append(verb)
                if scenario == 1 && verb == .batteryChargingOn && !gated {
                    gated = true
                    await withCheckedContinuation { gate = $0 }
                    try Task.checkCancellation()
                }
                if fail { throw RootHelperClient.Failure.executionFailed(70) }
                if scenario != 4 && verb.rawValue.hasPrefix("charge-limit-") {
                    limit = Int(verb.rawValue.split(separator: "-").last ?? "")
                }
            }, installed: { true }, version: { RootContract.version }, create: { _ in 1 }, release: { _ in },
                readLimit: { limit }))
            if scenario <= 5 || scenario == 8 {
                if [2, 3, 4].contains(scenario) { prefs.set(.batteryChargeLimit, true) }
                if scenario == 5 {
                    prefs.set(.keepAwake, true)
                    prefs.set(.lidClosedAwake, true)
                }
                if scenario == 8 { prefs.set(.batterySailing, true); fail = true }
                module.start()
                await settle()
                if scenario == 1 {
                    module.refreshHelper()
                    await settle()
                    gate?.resume()
                    await settle()
                    await module.evaluate(now: .now)
                    check(!prefs.batteryDirtyVerbs.contains("battery-charging"), "repair-survives-schedule")
                } else if scenario == 2 {
                    fail = true
                    prefs.batteryChargePercent = 70
                    await module.evaluate(now: .now)
                    fail = false
                    prefs.set(.batteryChargeLimit, false)
                    await settle()
                    await module.evaluate(now: Date.now.addingTimeInterval(3600))
                    check(limit == nil, "failed-limit-keeps-confirmed-owner")
                } else if scenario == 3 || scenario == 4 {
                    module.stop()
                    await module.waitUntilIdle()
                    check(scenario == 3 ? limit == 70 : !calls.contains(.chargeLimitOff),
                          scenario == 3 ? "restore-prior-limit" : "external-off-before-adoption")
                } else if scenario == 5 {
                    fail = true
                    module.stop()
                    await module.waitUntilIdle()
                    let before = calls.filter { $0 == .batterySleepOn }.count
                    await module.evaluate(now: Date.now.addingTimeInterval(3600))
                    check(module.failure != nil && calls.filter { $0 == .batterySleepOn }.count > before,
                          "failed-sleep-undo-retries")
                } else {
                    for offset in 1...100 { await module.evaluate(now: Date.now.addingTimeInterval(Double(offset * 60))) }
                    check(calls.filter { $0 == .batteryChargingOff }.count <= 8, "permanent-failure-bounded")
                }
                module.stop()
                await module.waitUntilIdle()
            } else {
                var saved = FanControl.Mode.max
                var fanCalls: [RootContract.Command] = []
                var data: Data?
                if scenario == 7 {
                    let seed = FanControl(persist: { data = $0 }, runner: { _ in })
                    seed.set(.max)
                    await seed.waitUntilIdle()
                }
                let fans = FanControl(
                    confirmed: { saved = $0 }, journalData: data, persist: { data = $0 }, runner: { command in
                        await MainActor.run { fanCalls.append(command) }
                        throw RootHelperClient.Failure.timedOut
                    })
                if scenario == 6 { fans.set(.max) } else {
                    fans.restore(preservingPreference: true, silently: true)
                }
                await fans.waitUntilIdle()
                let before = fanCalls.count
                fans.restore(preservingPreference: true)
                await fans.waitUntilIdle()
                let owned = data.flatMap { try? JSONDecoder().decode(FanOwnershipJournal.self, from: $0) }
                check(scenario == 6 ? owned?.needsUndo == true && fanCalls.count == before
                      : saved == .max && fanCalls == [.fansAuto] && owned?.needsUndo == true,
                      scenario == 6 ? "uncertain-fan-undo-survives" : "silent-restore-preserves-preference")
                if scenario == 6 {
                    var relaunchedCalls = 0
                    let relaunched = FanControl(journalData: data, runner: { _ in
                        await MainActor.run { relaunchedCalls += 1 }
                    })
                    relaunched.set(.max)
                    await relaunched.waitUntilIdle()
                    check(relaunchedCalls == 0 && relaunched.failure != nil,
                          "fan-relaunch-retains-undo-backoff")
                }
            }
        }
        if failures > 0 { exit(1) }
    }

    static func journalTable() throws {
        let now = Date(timeIntervalSince1970: 1000)
        typealias Key = BatteryOwnershipJournal.Key
        precondition(Key.allCases.map(\.rawValue) == ["charge-limit", "battery-charging", "battery-adapter", "battery-sleep"],
                     "Journal keys are persisted; a renamed raw value orphans a saved effect")
        precondition(Key.released.map(\.rawValue) == ["battery-adapter", "battery-charging", "battery-sleep"])
        let keyed: [(RootContract.Command, Key, Bool)] = [
            (.chargeLimit60, .chargeLimit, false),
            (.chargeLimit70, .chargeLimit, false),
            (.chargeLimit80, .chargeLimit, false),
            (.chargeLimit90, .chargeLimit, false),
            (.chargeLimitOff, .chargeLimit, false),
            (.batteryChargingOn, .charging, true),
            (.batteryChargingOff, .charging, false),
            (.batteryAdapterOn, .adapter, true),
            (.batteryAdapterOff, .adapter, false),
            (.batterySleepOn, .sleep, true),
            (.batterySleepOff, .sleep, false),
        ]
        for (verb, key, releases) in keyed {
            precondition(verb.batteryJournalKey == key, "\(verb) journals under \(key)")
            precondition(verb.rawValue.hasPrefix(key.rawValue + "-"), "\(key) is the stem of \(verb)")
            precondition((key.release == verb) == releases, "\(verb) release")
        }
        let unkeyed = RootContract.Command.allCases.filter { verb in !keyed.contains { $0.0 == verb } }
        precondition(unkeyed.allSatisfy { $0.batteryJournalKey == nil }, "Only battery effects are journaled")
        precondition(Key.chargeLimit.release == nil)
        precondition(Key.released.allSatisfy { $0.release?.rawValue == $0.rawValue + "-on" })
        for percent in [60, 70, 80, 90] {
            precondition(RootContract.Command(chargeLimit: percent)?.chargeLimitPercent == percent)
        }
        precondition(RootContract.Command.chargeLimitOff.chargeLimitPercent == nil)
        precondition(RootContract.Command.chargeLimitRead.chargeLimitPercent == nil)
        let table: [(Key, String, String)] = [
            (.charging, "battery-charging-off", "battery-charging-on"),
            (.sleep, "battery-sleep-off", "battery-sleep-on"),
            (.chargeLimit, "charge-limit-80", "charge-limit-70"),
        ]
        for (typed, verb, undo) in table {
            let key = typed.rawValue
            var journal = BatteryOwnershipJournal()
            journal.captureLimit(70)
            journal.begin(typed, verb: verb, undo: undo)
            journal.fail(typed, now: now)
            journal = try JSONDecoder().decode(BatteryOwnershipJournal.self,
                from: JSONEncoder().encode(journal))
            precondition(journal.effects[key]?.applied == nil && journal.effects[key]?.intent == verb)
            journal.begin(typed, verb: undo, undo: undo)
            for attempt in 0..<6 {
                journal.fail(typed, now: now.addingTimeInterval(Double(attempt * 3600)))
            }
            journal = try JSONDecoder().decode(BatteryOwnershipJournal.self,
                from: JSONEncoder().encode(journal))
            precondition(!journal.canRun(typed, verb: undo, now: .distantFuture, releasing: true))
            precondition(journal.effects[key]?.undo == undo)
            journal.succeed(typed, verb: undo, releasing: true)
            precondition(journal.effects[key] == nil)
        }
        var journal = BatteryOwnershipJournal()
        journal.captureLimit(70)
        journal.begin(.chargeLimit, verb: "charge-limit-80", undo: "charge-limit-70")
        journal.succeed(.chargeLimit, verb: "charge-limit-80", releasing: false)
        journal.begin(.chargeLimit, verb: "charge-limit-70", undo: "charge-limit-70")
        journal.fail(.chargeLimit, now: now)
        precondition(journal.effects["charge-limit"]?.applied == "charge-limit-80")
        precondition(journal.userChangedLimit(nil), "External charge-limit off must release ownership")
        precondition(!journal.userChangedLimit(80))
        precondition(journal.userChangedLimit(90))
        journal.begin(.chargeLimit, verb: "charge-limit-off", undo: "charge-limit-70")
        precondition(!journal.userChangedLimit(nil), "Pending off is owned intent")
        journal.succeed(.chargeLimit, verb: "charge-limit-off", releasing: false)
        precondition(!journal.userChangedLimit(nil), "Applied off is owned state")
        var fans = FanOwnershipJournal()
        fans.begin("max")
        fans.fail(now: now)
        fans.begin("auto")
        fans.fail(now: now)
        fans = try JSONDecoder().decode(FanOwnershipJournal.self, from: JSONEncoder().encode(fans))
        precondition(fans.needsUndo && fans.applied == "auto")
        precondition(!fans.mayRetry(now: now))
        for attempt in 1..<6 { fans.fail(now: now.addingTimeInterval(Double(attempt * 3600))) }
        fans = try JSONDecoder().decode(FanOwnershipJournal.self, from: JSONEncoder().encode(fans))
        precondition(!fans.mayRetry(now: .distantFuture) && fans.needsUndo)
        fans.succeed("auto")
        precondition(!fans.needsUndo)
        journal.begin(.sleep, verb: "battery-sleep-off", undo: "battery-sleep-on")
        journal.begin(.charging, verb: "battery-charging-off", undo: "battery-charging-on")
        journal.release(.sleep)
        precondition(journal.effect(.charging) != nil && journal.effect(.sleep) == nil)
        journal.release(.chargeLimit)
        journal.captureLimit(85)
        precondition(journal.limitUndo == nil)
        print("PASS: journal-crash-relaunch-failure-table")
    }
}
