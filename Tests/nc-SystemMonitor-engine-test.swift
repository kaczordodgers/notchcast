// notchcast-sources: Tinycast/Features/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorStore*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorProcessService.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorAlerts.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/MonitorAlertPreferences.swift
// notchcast-sources: Tinycast/Features/SystemTools/Model/KillProcessEntry.swift
// notchcast-sources: Tinycast/Features/SystemTools/Service/KillProcessService.swift
// notchcast-kit: core
import Foundation

@MainActor
final class MonitorEngineProbe {
    var samples = 0
    var intervals: [Duration] = []
    var sleepers: [CheckedContinuation<Void, Never>] = []
    var phases: [SpeedTestPhase] = []
    var measurements: [CheckedContinuation<SpeedTestResult.Measurement, any Error>] = []
    var lookups: [CheckedContinuation<String?, Never>] = []
    var lookupCount = 0
    var pendingSamples: [CheckedContinuation<MonitorSnapshot, Never>] = []

    func sample() -> MonitorSnapshot {
        samples += 1
        return MonitorSnapshot(battery: BatteryReading.decode(properties: ["Temperature": 4100]))
    }

    func gatedSample() async -> MonitorSnapshot {
        await withCheckedContinuation { pendingSamples.append($0) }
    }

    func sleep(_ duration: Duration) async throws {
        intervals.append(duration)
        await withCheckedContinuation { sleepers.append($0) }
        try Task.checkCancellation()
    }

    func measure(_ phase: SpeedTestPhase) async throws -> SpeedTestResult.Measurement {
        phases.append(phase)
        return try await withCheckedThrowingContinuation { measurements.append($0) }
    }

    func lookup() async -> String? {
        lookupCount += 1
        return await withCheckedContinuation { lookups.append($0) }
    }

    func finishMeasurement(_ speed: Double = 100) {
        measurements.removeFirst().resume(returning: .init(
            throughputMbps: speed, responsivenessRPM: 1200, baseRTTMilliseconds: 12))
    }

    func store() -> MonitorStore {
        MonitorStore(sample: { await self.sample() }, measureSpeed: { try await self.measure($0) },
                     lookupPublicIP: { await self.lookup() }, sleep: { try await self.sleep($0) })
    }
}

@main
@MainActor
struct MonitorEngineTests {
    static func until(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Fake operation did not settle")
            await Task.yield()
        }
    }

    static func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    static func main() async throws {
        await demand()
        await staleSample()
        await speedTests()
        await publicIP()
        alerts()
        processes()
        try parsing()
        print("PASS: token lifetime, 2 s cadence, speed phases/cancellation/history, session IP, battery alerts, safe quit")
    }

    static func demand() async {
        let probe = MonitorEngineProbe()
        var store: MonitorStore? = probe.store()
        store?.start()
        await settle()
        precondition(probe.samples == 0 && probe.phases.isEmpty && probe.lookupCount == 0)
        var first = store?.beginDemand()
        let second = store?.beginDemand()
        precondition(store?.demand == 2)
        await until { probe.sleepers.count == 1 && store?.latest.battery != nil }
        precondition(probe.samples == 1 && probe.intervals == [.seconds(2)])
        first = nil
        precondition(store?.demand == 1 && first == nil)
        probe.sleepers.removeFirst().resume()
        await until { probe.sleepers.count == 1 && probe.samples == 2 }
        second?.cancel()
        second?.cancel()
        precondition(store?.demand == 0)
        probe.sleepers.removeFirst().resume()
        await settle()
        precondition(probe.samples == 2)
        let third = store?.beginDemand()
        await until { probe.samples == 3 && probe.sleepers.count == 1 }
        store?.stop()
        probe.sleepers.removeFirst().resume()
        await settle()
        precondition(probe.samples == 3 && store?.demand == 1)
        store?.start()
        await until { probe.samples == 4 && probe.sleepers.count == 1 }
        weak var weakStore = store
        store = nil
        precondition(weakStore == nil)
        third?.cancel()
        probe.sleepers.removeFirst().resume()
        await settle()
        precondition(probe.samples == 4)
    }

    static func speedTests() async {
        let probe = MonitorEngineProbe()
        let store = probe.store()
        precondition(!store.startSpeedTest())
        store.start()
        for index in 0..<12 {
            precondition(store.startSpeedTest() && !store.startSpeedTest())
            precondition(store.speedTestState == .running(.download))
            await until { probe.measurements.count == 1 }
            probe.finishMeasurement(Double(index))
            await until { store.speedTestState == .running(.upload) && probe.measurements.count == 1 }
            precondition(!store.startSpeedTest())
            probe.finishMeasurement(Double(index + 1))
            await until { store.speedTestState == .completed }
        }
        precondition(store.speedTestResults.count == 10)
        precondition(store.speedTestResults.map(\.downloadMbps) == (2..<12).reversed().map(Double.init))
        precondition(store.speedTestResults.first?.uploadMbps == 12)
        precondition(probe.phases == Array(repeating: [.download, .upload], count: 12).flatMap { $0 })
        let saved = store.speedTestResults
        precondition(store.startSpeedTest())
        await until { probe.measurements.count == 1 }
        store.cancelSpeedTest()
        precondition(store.speedTestState == .cancelling && !store.startSpeedTest())
        probe.finishMeasurement()
        await until { store.speedTestState == .cancelled }
        precondition(probe.phases.last == .download && store.speedTestResults == saved)
        precondition(store.startSpeedTest())
        await until { probe.measurements.count == 1 }
        probe.finishMeasurement()
        await until { probe.measurements.count == 1 && store.speedTestState == .running(.upload) }
        store.stop()
        store.start()
        precondition(!store.startSpeedTest())
        probe.finishMeasurement()
        await until { store.speedTestState == .cancelled }
        precondition(store.speedTestResults == saved)
        precondition(store.startSpeedTest())
        await until { probe.measurements.count == 1 }
        probe.measurements.removeFirst().resume(throwing: CocoaError(.coderInvalidValue))
        await until { store.speedTestState == .failed }
        precondition(store.speedTestResults == saved)
        precondition(store.startSpeedTest())
        store.cancelSpeedTest()
        await until { store.speedTestState == .cancelled }
        precondition(probe.measurements.isEmpty && store.demand == 0 && probe.samples == 0)
        store.stop()
    }

    static func staleSample() async {
        let probe = MonitorEngineProbe()
        let store = MonitorStore(sample: { await probe.gatedSample() })
        store.start()
        let first = store.beginDemand()
        await until { probe.pendingSamples.count == 1 }
        first.cancel()
        let second = store.beginDemand()
        await until { probe.pendingSamples.count == 2 }
        let stale = MonitorSnapshot(battery: BatteryReading.decode(properties: ["Temperature": 4100]))
        probe.pendingSamples.removeFirst().resume(returning: stale)
        await settle()
        precondition(store.latest.battery == nil && store.histories.isEmpty)
        let current = MonitorSnapshot(battery: BatteryReading.decode(properties: ["Temperature": 3500]))
        probe.pendingSamples.removeFirst().resume(returning: current)
        await until { store.latest.id == current.id }
        second.cancel()
        store.stop()
    }

    static func publicIP() async {
        let probe = MonitorEngineProbe()
        let store = probe.store()
        store.start()
        await settle()
        precondition(probe.lookupCount == 0 && store.publicIP == nil)
        precondition(store.requestPublicIP() && !store.requestPublicIP() && store.isFetchingPublicIP)
        await until { probe.lookups.count == 1 }
        probe.lookups.removeFirst().resume(returning: nil)
        await until { !store.isFetchingPublicIP }
        precondition(store.publicIPLookupFailed && store.requestPublicIP())
        await until { probe.lookups.count == 1 }
        store.stop()
        precondition(!store.requestPublicIP() && !store.isFetchingPublicIP)
        store.start()
        precondition(store.requestPublicIP())
        await until { probe.lookups.count == 2 }
        probe.lookups.removeFirst().resume(returning: "203.0.113.10")
        await settle()
        precondition(store.publicIP == nil && store.isFetchingPublicIP)
        probe.lookups.removeFirst().resume(returning: "2001:db8::1")
        await until { !store.isFetchingPublicIP }
        precondition(store.publicIP == "2001:db8::1" && !store.publicIPLookupFailed)
        store.stop()
        store.start()
        precondition(!store.requestPublicIP() && probe.lookupCount == 3)
        store.stop()
    }

    static func alerts() {
        let suite = "monitor-engine.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(preferences.monitorBatteryTemperature == 40)
        let configured = preferences.monitorAlertRules[.batteryTemperature]
        precondition(configured?.threshold == 40 && configured?.recoverValue == 35)
        precondition(MonitorAlertRule.defaults[.batteryTemperature]?.recoverValue == 35)
        preferences.monitorBatteryTemperature = 45
        let restored = NotchcastPreferences(suiteName: suite)
        precondition(restored.monitorBatteryTemperature == 45)
        precondition(restored.monitorAlertRules[.batteryTemperature]?.recoverValue == 40)
        var fires = 0
        let alerts = MonitorAlerts { _ in fires += 1 }
        func evaluate(_ temperature: Double?, time: Double) {
            let battery = temperature.flatMap { BatteryReading.decode(properties: ["Temperature": $0 * 100]) }
            alerts.evaluate(MonitorSnapshot(battery: battery), rules: [.batteryTemperature: configured!],
                            enabled: true, demand: 1, at: Date(timeIntervalSince1970: time))
        }
        for temperature in [41.0, 41, 40, 41, 41] { evaluate(temperature, time: 0) }
        precondition(fires == 0)
        evaluate(nil, time: 0)
        for _ in 0..<3 { evaluate(41, time: 0) }
        precondition(fires == 1)
        evaluate(36, time: 1000)
        for _ in 0..<3 { evaluate(41, time: 1000) }
        precondition(fires == 1)
        evaluate(35, time: 1000)
        for _ in 0..<3 { evaluate(41, time: 1000) }
        precondition(fires == 2)
    }

    static func processes() {
        let identity = ProcessReading.Identity(pid: 500, startSeconds: 100, startMicroseconds: 12)
        func entry(uid: UInt32 = 501, start: UInt64 = 100) -> KillProcessEntry {
            .init(pid: 500, parentPID: 1, uid: uid, startSeconds: start, startMicroseconds: 12,
                  path: "/Applications/Fake.app/Contents/MacOS/Fake")
        }
        var quits = 0
        var forces = 0
        var lookups = 0
        var service = MonitorProcessService(uid: 501, ownPID: 600, lookup: { _ in entry() }, application: { _ in
            .init(quit: { quits += 1; return true }, forceQuit: { forces += 1; return true })
        })
        let store = MonitorStore()
        precondition(store.quitProcess(identity, service: service) == .requested)
        precondition(store.quitProcess(identity, force: true, service: service) == .requested)
        precondition(quits == 1 && forces == 1)
        service.ownPID = 500
        precondition(store.quitProcess(identity, service: service) == .protectedProcess)
        service.ownPID = 600
        service.lookup = { _ in entry(uid: 502) }
        precondition(store.quitProcess(identity, service: service) == .protectedProcess)
        service.lookup = { _ in nil }
        precondition(store.quitProcess(identity, service: service) == .unavailable)
        service.lookup = { _ in entry(start: 101) }
        precondition(store.quitProcess(identity, service: service) == .staleIdentity)
        service.lookup = { _ in
            lookups += 1
            return entry(start: lookups < 3 ? 100 : 101)
        }
        precondition(store.quitProcess(identity, service: service) == .staleIdentity)
        service.lookup = { _ in entry() }
        service.application = { _ in nil }
        precondition(store.quitProcess(identity, service: service) == .unavailable)
        service.application = { _ in .init(quit: { false }, forceQuit: { false }) }
        precondition(store.quitProcess(identity, service: service) == .rejected)
        precondition(store.quitProcess(identity, force: true, service: service) == .rejected)
        precondition(quits == 1 && forces == 1)
    }

    static func parsing() throws {
        let download = try SpeedTestResult.parse(
            Data(#"{"dl_throughput":125000000,"dl_responsiveness":1000,"base_rtt":12}"#.utf8), phase: .download)
        let upload = try SpeedTestResult.parse(
            Data(#"{"ul_throughput":42000000,"ul_responsiveness":1200}"#.utf8), phase: .upload)
        precondition(download.throughputMbps == 125 && download.responsivenessRPM == 1000)
        precondition(upload.throughputMbps == 42 && upload.baseRTTMilliseconds == nil)
        for json in ["{}", #"{"dl_throughput":true}"#, #"{"dl_throughput":-1}"#] {
            do {
                _ = try SpeedTestResult.parse(Data(json.utf8), phase: .download)
                preconditionFailure("Invalid phase JSON accepted")
            } catch {}
        }
    }
}
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
