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
    private(set) var latest = MonitorSnapshot()
    private(set) var histories: [String: MonitorHistory] = [:]
    private(set) var demand = 0
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let sample: (@Sendable () async -> MonitorSnapshot)?

    init(sample: (@Sendable () async -> MonitorSnapshot)? = nil) { self.sample = sample }

    func start() { enabled = true; update() }
    func stop() { enabled = false; update() }
    func acquire() { demand += 1; update() }
    func release() { demand = max(0, demand - 1); update() }

    private func update() {
        guard enabled, let cadence = MonitorCadence.next(isVisible: demand > 0) else {
            generation += 1
            worker?.cancel()
            worker = nil
            return
        }
        guard worker == nil else { return }
        let identity = generation
        let sample = sample
        worker = Task { [weak self] in
            let stream = AsyncStream<MonitorSnapshot> { continuation in
                let producer = Task.detached {
                    var cpu = CPUSampler()
                    var disk = DiskSampler()
                    var network = NetworkSampler()
                    var sensors = SMCSensorReader()
                    var processes = ProcessSampler()
                    while !Task.isCancelled {
                        let reading: MonitorSnapshot
                        if let sample {
                            reading = await sample()
                        } else {
                            reading = MonitorSnapshot(
                                cpu: cpu.sample(), memory: MemorySampler().read(),
                                volumes: disk.read(), disk: disk.sample(now: ProcessInfo.processInfo.systemUptime),
                                network: network.sample(), gpu: GPUService().read(),
                                battery: BatteryService().read(), sensors: sensors.read(), processes: processes.sample())
                        }
                        guard !Task.isCancelled else { break }
                        continuation.yield(reading)
                        do { try await Task.sleep(for: .seconds(cadence.interval)) } catch { break }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in producer.cancel() }
            }
            for await reading in stream {
                guard !Task.isCancelled, let self, self.generation == identity,
                      self.enabled, self.demand > 0 else { break }
                self.latest = reading
                for (key, value) in reading.series {
                    self.histories[key, default: MonitorHistory()].append(value)
                }
            }
        }
    }
}
