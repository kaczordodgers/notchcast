import Foundation
import Observation

nonisolated struct MonitorSnapshot: Sendable {
    let id = UUID()
    var cpu: CPUReading?
    var memory: MemoryReading?
    var volumes: [DiskVolume] = []
    var disk: [DiskIOReading] = []
    var network: NetworkReading?
    var gpu: [GPUReading] = []
    var battery: BatteryReading?
    var sensors: SMCSensorReading?
    var processes: ProcessReading?

    var series: [String: Double] {
        var values: [String: Double] = [:]
        values["cpu"] = cpu?.usage?.totalPercent
        values["memory"] = memory.map { Double($0.used) }
        values["network.down"] = network?.downBytesPerSecond
        values["network.up"] = network?.upBytesPerSecond
        values["battery"] = battery?.percent
        values["temperature.cpu"] = sensors?.cpuTemperature
        values["temperature.gpu"] = sensors?.gpuTemperature
        values["power"] = sensors?.systemPowerWatts
        for reading in gpu { values["gpu.\(reading.id)"] = reading.utilizationPercent }
        for reading in disk {
            values["disk.\(reading.id).read"] = reading.readBytesPerSecond
            values["disk.\(reading.id).write"] = reading.writeBytesPerSecond
        }
        for fan in sensors?.fans ?? [] { values["fan.\(fan.index)"] = fan.currentRPM }
        return values
    }
}

@MainActor
@Observable
final class MonitorStore {
    var ejectStates: [String: DiskEjectState] = [:]
    var ejectLifecycle: (enabled: Bool, generation: Int) { (enabled, ejectGeneration) }
    @ObservationIgnored private var ejectGeneration = 0
    @MainActor
    final class DemandToken {
        private var end: (() -> Void)?

        fileprivate init(end: @escaping () -> Void) { self.end = end }

        func cancel() {
            end?()
            end = nil
        }

        isolated deinit { end?() }
    }

    enum SpeedTestState: Equatable {
        case idle
        case running(SpeedTestPhase)
        case cancelling
        case completed
        case cancelled
        case failed
    }

    private(set) var latest = MonitorSnapshot()
    private(set) var histories: [String: MonitorHistory] = [:]
    private(set) var demand = 0
    private(set) var speedTestState = SpeedTestState.idle
    private(set) var speedTestResults: [SpeedTestResult] = []
    private(set) var publicIP: String?
    private(set) var isFetchingPublicIP = false
    private(set) var publicIPLookupFailed = false
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var visibleDemand = 0
    @ObservationIgnored private var samplingAlertsOnly: Bool?
    @ObservationIgnored private let alertSample: (@Sendable () async -> MonitorSnapshot)?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var samplingSleep: Task<Void, Never>?
    @ObservationIgnored private var latestIsAlertsOnly = false
    @ObservationIgnored private let sample: (@Sendable () async -> MonitorSnapshot)?
    @ObservationIgnored private let measureSpeed: @Sendable (SpeedTestPhase) async throws -> SpeedTestResult.Measurement
    @ObservationIgnored private let lookupPublicIP: @Sendable () async -> String?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var speedTestTask: Task<Void, Never>?
    @ObservationIgnored private var publicIPTask: Task<Void, Never>?
    @ObservationIgnored private var publicIPIdentity: UUID?

    init(sample: (@Sendable () async -> MonitorSnapshot)? = nil,
         alertSample: (@Sendable () async -> MonitorSnapshot)? = nil,
         measureSpeed: @escaping @Sendable (SpeedTestPhase) async throws -> SpeedTestResult.Measurement = {
             try await SpeedTestRunner().run($0)
         },
         lookupPublicIP: @escaping @Sendable () async -> String? = { await NetworkPublicIPService().lookup() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sample = sample
        self.alertSample = alertSample
        self.measureSpeed = measureSpeed
        self.lookupPublicIP = lookupPublicIP
        self.sleep = sleep
    }

    isolated deinit {
        samplingSleep?.cancel()
        worker?.cancel()
        speedTestTask?.cancel()
        publicIPTask?.cancel()
    }

    func start() { enabled = true; update() }
    func stop() {
        enabled = false
        ejectGeneration += 1
        update()
        cancelSpeedTest()
        publicIPIdentity = nil
        publicIPTask?.cancel()
        publicIPTask = nil
        isFetchingPublicIP = false
    }

    func beginDemand(alertsOnly: Bool = false) -> DemandToken {
        demand += 1
        if !alertsOnly { visibleDemand += 1 }
        update()
        return DemandToken { [weak self] in
            guard let self else { return }
            self.demand -= 1
            if !alertsOnly { self.visibleDemand -= 1 }
            self.update()
        }
    }

    @discardableResult
    func startSpeedTest() -> Bool {
        guard enabled, speedTestTask == nil else { return false }
        speedTestState = .running(.download)
        let measure = measureSpeed
        speedTestTask = Task { [weak self] in
            defer { self?.speedTestTask = nil }
            do {
                try Task.checkCancellation()
                let download = try await measure(.download)
                try Task.checkCancellation()
                self?.speedTestState = .running(.upload)
                let upload = try await measure(.upload)
                try Task.checkCancellation()
                guard let self else { return }
                self.speedTestResults.insert(SpeedTestResult(
                    downloadMbps: download.throughputMbps, uploadMbps: upload.throughputMbps,
                    responsivenessRPM: upload.responsivenessRPM ?? download.responsivenessRPM,
                    baseRTTMilliseconds: download.baseRTTMilliseconds ?? upload.baseRTTMilliseconds), at: 0)
                self.speedTestResults = Array(self.speedTestResults.prefix(10))
                self.speedTestState = .completed
            } catch {
                self?.speedTestState = Task.isCancelled || error is CancellationError ? .cancelled : .failed
            }
        }
        return true
    }

    func cancelSpeedTest() {
        guard let speedTestTask else { return }
        speedTestState = .cancelling
        speedTestTask.cancel()
    }

    @discardableResult
    func requestPublicIP() -> Bool {
        guard enabled, publicIP == nil, publicIPTask == nil else { return false }
        let identity = UUID()
        publicIPIdentity = identity
        isFetchingPublicIP = true
        publicIPLookupFailed = false
        let lookup = lookupPublicIP
        publicIPTask = Task { [weak self] in
            let address = await lookup()
            guard !Task.isCancelled, let self, self.publicIPIdentity == identity else { return }
            self.publicIP = address
            self.publicIPLookupFailed = address == nil
            self.isFetchingPublicIP = false
            self.publicIPTask = nil
        }
        return true
    }

    private func update() {
        let alertsOnly = visibleDemand == 0
        if samplingAlertsOnly == true, !alertsOnly {
            if latestIsAlertsOnly { latest = MonitorSnapshot() }
            latestIsAlertsOnly = false
            samplingSleep?.cancel()
        }
        samplingAlertsOnly = alertsOnly
        guard enabled, let cadence = MonitorCadence.next(isVisible: demand > 0) else {
            generation += 1
            samplingSleep?.cancel()
            worker?.cancel()
            worker = nil
            return
        }
        guard worker == nil else { return }
        let identity = generation
        let sample = sample
        let alertSample = alertSample
        worker = Task { [weak self] in
            let stream = AsyncStream<(MonitorSnapshot, Bool)> { continuation in
                let producer = Task.detached { [weak self] in
                    var cpu = CPUSampler()
                    var disk = DiskSampler()
                    var network = NetworkSampler()
                    var sensors = SMCSensorReader()
                    var processes = ProcessSampler()
                    while !Task.isCancelled {
                        guard let alertsOnly = await self?.samplingAlertsOnly else { break }
                        let sampler = alertsOnly ? alertSample : sample
                        let reading: MonitorSnapshot
                        if let sampler {
                            reading = await sampler()
                        } else if alertsOnly {
                            _ = disk.sample(now: ProcessInfo.processInfo.systemUptime)
                            _ = network.sample()
                            reading = MonitorSnapshot(
                                cpu: cpu.sample(), memory: MemorySampler().read(),
                                volumes: disk.read(bootOnly: true), battery: BatteryService().read(),
                                sensors: sensors.read(alertsOnly: true))
                        } else {
                            reading = MonitorSnapshot(
                                cpu: cpu.sample(), memory: MemorySampler().read(),
                                volumes: disk.read(), disk: disk.sample(now: ProcessInfo.processInfo.systemUptime),
                                network: network.sample(), gpu: GPUService().read(),
                                battery: BatteryService().read(), sensors: sensors.read(), processes: processes.sample())
                        }
                        guard !Task.isCancelled else { break }
                        continuation.yield((reading, alertsOnly))
                        // The store hands out the nap and is released while it runs, so it can deinit.
                        guard let nap = await self?.samplingNap(interval: cadence.interval,
                                                                alertsOnly: alertsOnly, identity: identity)
                        else { break }
                        await withTaskCancellationHandler { await nap.value } onCancel: { nap.cancel() }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in producer.cancel() }
            }
            for await (reading, alertsOnly) in stream {
                guard !Task.isCancelled, let self, self.generation == identity,
                      self.enabled, self.demand > 0 else { break }
                guard !alertsOnly || self.visibleDemand == 0 else { continue }
                self.latest = reading
                self.latestIsAlertsOnly = alertsOnly
                for (key, value) in alertsOnly ? [:] : reading.series {
                    self.histories[key, default: MonitorHistory()].append(value)
                }
            }
        }
    }

    /// A mode change since the sample, or a stale worker, gets no nap so the next sample runs at once.
    private func samplingNap(interval: TimeInterval, alertsOnly: Bool, identity: Int) -> Task<Void, Never> {
        guard generation == identity, samplingAlertsOnly == alertsOnly else { return Task {} }
        let sleep = sleep
        let task = Task.detached { _ = try? await sleep(.seconds(interval)) }
        samplingSleep = task
        return task
    }
}
