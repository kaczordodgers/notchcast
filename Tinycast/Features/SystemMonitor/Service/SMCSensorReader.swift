import Darwin
import Foundation

nonisolated struct SMCSensorReader: Sendable {
    private let client: SMCClient?
    private let cpuKeys: [String]
    private(set) var discoveredCPUKeys: [String] = []
    private(set) var discoveredGPUKeys: [String] = []
    private var nextKeyIndex: UInt32 = 0
    // shortcut: one retry on the next read, then dropped; count attempts if that proves too few.
    private var failedKeyIndices: [UInt32] = []
    private var keyCount: UInt32?

    init(client: SMCClient? = SMCClient(), brand: String? = nil) {
        self.client = client
        cpuKeys = TemperatureSensorPolicy.cpuKeys(brand: brand ?? Self.cpuBrand())
    }

    mutating func read(alertsOnly: Bool = false) -> SMCSensorReading {
        guard let client else {
            return SMCSensorReading(cpuTemperature: nil, gpuTemperature: nil,
                                    systemPowerWatts: nil, fans: [])
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.045
        let watts = alertsOnly ? nil : SMCSensorReading.powerWatts(client.value("PSTR"))
        let fans = alertsOnly ? [] : fans(client, deadline: deadline)
        let fixedCPU = temperatures(cpuKeys, client: client, deadline: deadline)
        let fallbackCPU = fixedCPU.isEmpty
            ? temperatures(TemperatureSensorPolicy.fallbackCPUKeys, client: client, deadline: deadline) : []
        let fixedGPU = alertsOnly ? [] : temperatures(TemperatureSensorPolicy.gpuKeys, client: client, deadline: deadline)
        let needsCPU = fixedCPU.isEmpty && fallbackCPU.isEmpty
        if needsCPU || (!alertsOnly && fixedGPU.isEmpty) {
            discover(needsCPU: needsCPU, needsGPU: !alertsOnly && fixedGPU.isEmpty, deadline: deadline,
                     keyCount: client.keyCount, key: client.key(at:))
        }
        let cpu = !fixedCPU.isEmpty ? fixedCPU : !fallbackCPU.isEmpty ? fallbackCPU
            : temperatures(discoveredCPUKeys, client: client, deadline: deadline)
        let gpu = alertsOnly ? [] : fixedGPU.isEmpty
            ? temperatures(discoveredGPUKeys, client: client, deadline: deadline) : fixedGPU
        return SMCSensorReading(cpuTemperature: TemperatureSensorPolicy.average(cpu),
                                gpuTemperature: TemperatureSensorPolicy.hottest(gpu),
                                systemPowerWatts: watts, fans: fans,
                                maximumCPUTemperature: TemperatureSensorPolicy.hottest(cpu))
    }

    private func temperatures(_ keys: [String], client: SMCClient, deadline: Double) -> [Double] {
        Self.temperatures(keys, deadline: deadline, value: client.value)
    }

    static func temperatures(_ keys: [String], deadline: Double,
                             value: (String) -> Double?) -> [Double] {
        var readings: [Double] = []
        for key in keys {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            if let value = value(key), TemperatureSensorPolicy.hottest([value]) != nil {
                readings.append(value)
            }
        }
        return readings
    }

    mutating func discover(needsCPU: Bool, needsGPU: Bool, deadline: Double,
                           keyCount count: () -> UInt32?, key lookup: (UInt32) -> String?) {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return }
        if keyCount == nil { keyCount = count() }
        guard let keyCount else { return }
        let includesTf = cpuKeys.contains { $0.hasPrefix("Tf") }
        var retries = failedKeyIndices[...]
        failedKeyIndices = []
        defer { failedKeyIndices += retries }
        while ProcessInfo.processInfo.systemUptime < deadline {
            let key: String?
            if let index = retries.popFirst() {
                key = lookup(index)
            } else if nextKeyIndex < keyCount {
                key = lookup(nextKeyIndex)
                if key == nil { failedKeyIndices.append(nextKeyIndex) }
                nextKeyIndex += 1
            } else {
                break
            }
            guard let key else { continue }
            if needsCPU, TemperatureSensorPolicy.isCPUKey(key, includesTf: includesTf) {
                discoveredCPUKeys.append(key)
            } else if needsGPU, TemperatureSensorPolicy.isGPUKey(key) {
                discoveredGPUKeys.append(key)
            }
        }
    }

    private func fans(_ client: SMCClient, deadline: Double) -> [SMCSensorReading.Fan] {
        guard let count = client.value("FNum"), (0...10).contains(count), count.rounded() == count else { return [] }
        var result: [SMCSensorReading.Fan] = []
        for index in 0..<Int(count) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            result.append(SMCSensorReading.Fan(
                index: index, currentRPM: SMCSensorReading.fanRPM(client.value("F\(index)Ac")),
                minimumRPM: SMCSensorReading.fanRPM(client.value("F\(index)Mn")),
                maximumRPM: SMCSensorReading.fanRPM(client.value("F\(index)Mx"))))
        }
        return result
    }

    private static func cpuBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              (1...256).contains(size) else { return "" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
    }
}
