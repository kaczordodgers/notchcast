import Darwin
import Foundation

nonisolated struct SMCSensorReader: Sendable {
    private let client: SMCClient?
    private let cpuKeys: [String]
    private var discoveredCPUKeys: [String] = []
    private var discoveredGPUKeys: [String] = []
    private var nextKeyIndex: UInt32 = 0
    private var keyCount: UInt32?

    init(client: SMCClient? = SMCClient(), brand: String? = nil) {
        self.client = client
        cpuKeys = TemperatureSensorPolicy.cpuKeys(brand: brand ?? Self.cpuBrand())
    }

    mutating func read() -> SMCSensorReading {
        guard let client else {
            return SMCSensorReading(cpuTemperature: nil, gpuTemperature: nil,
                                    systemPowerWatts: nil, fans: [])
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.045
        let watts = SMCSensorReading.powerWatts(client.value("PSTR"))
        let fans = fans(client, deadline: deadline)
        let fixedCPU = temperatures(cpuKeys, client: client, deadline: deadline)
        let fallbackCPU = fixedCPU.isEmpty
            ? temperatures(TemperatureSensorPolicy.fallbackCPUKeys, client: client, deadline: deadline) : []
        let fixedGPU = temperatures(TemperatureSensorPolicy.gpuKeys, client: client, deadline: deadline)
        let needsCPU = fixedCPU.isEmpty && fallbackCPU.isEmpty
        if needsCPU || fixedGPU.isEmpty {
            discover(client, needsCPU: needsCPU, needsGPU: fixedGPU.isEmpty, deadline: deadline)
        }
        let cpu = !fixedCPU.isEmpty ? fixedCPU : !fallbackCPU.isEmpty ? fallbackCPU
            : temperatures(discoveredCPUKeys, client: client, deadline: deadline)
        let gpu = fixedGPU.isEmpty
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

    private mutating func discover(_ client: SMCClient, needsCPU: Bool, needsGPU: Bool, deadline: Double) {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return }
        if keyCount == nil { keyCount = client.keyCount() }
        guard let keyCount else { return }
        let includesTf = cpuKeys.contains { $0.hasPrefix("Tf") }
        while nextKeyIndex < keyCount, ProcessInfo.processInfo.systemUptime < deadline {
            let key = client.key(at: nextKeyIndex)
            nextKeyIndex += 1
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
