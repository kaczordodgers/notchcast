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
        var cpu = hottest(cpuKeys, client: client, deadline: deadline)
            ?? hottest(TemperatureSensorPolicy.fallbackCPUKeys, client: client, deadline: deadline)
        var gpu = hottest(TemperatureSensorPolicy.gpuKeys, client: client, deadline: deadline)
        if !discoveredCPUKeys.isEmpty {
            cpu = TemperatureSensorPolicy.hottest([cpu, hottest(discoveredCPUKeys, client: client,
                                                               deadline: deadline)].compactMap { $0 })
        }
        if !discoveredGPUKeys.isEmpty {
            gpu = TemperatureSensorPolicy.hottest([gpu, hottest(discoveredGPUKeys, client: client,
                                                               deadline: deadline)].compactMap { $0 })
        }
        if cpu == nil || gpu == nil || nextKeyIndex > 0 {
            discover(client, cpu: &cpu, gpu: &gpu, deadline: deadline)
        }
        return SMCSensorReading(cpuTemperature: cpu, gpuTemperature: gpu,
                                systemPowerWatts: watts, fans: fans)
    }

    private func hottest(_ keys: [String], client: SMCClient, deadline: Double) -> Double? {
        var readings: [Double] = []
        for key in keys {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            if let value = client.value(key) { readings.append(value) }
        }
        return TemperatureSensorPolicy.hottest(readings)
    }

    private mutating func discover(_ client: SMCClient, cpu: inout Double?, gpu: inout Double?, deadline: Double) {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return }
        if keyCount == nil { keyCount = client.keyCount() }
        guard let keyCount else { return }
        let includesTf = cpuKeys.contains { $0.hasPrefix("Tf") }
        while nextKeyIndex < keyCount, ProcessInfo.processInfo.systemUptime < deadline {
            let key = client.key(at: nextKeyIndex)
            nextKeyIndex += 1
            guard let key else { continue }
            if TemperatureSensorPolicy.isCPUKey(key, includesTf: includesTf), !cpuKeys.contains(key) {
                discoveredCPUKeys.append(key)
                cpu = TemperatureSensorPolicy.hottest([cpu, client.value(key)].compactMap { $0 })
            } else if TemperatureSensorPolicy.isGPUKey(key), !TemperatureSensorPolicy.gpuKeys.contains(key) {
                discoveredGPUKeys.append(key)
                gpu = TemperatureSensorPolicy.hottest([gpu, client.value(key)].compactMap { $0 })
            }
        }
    }

    private func fans(_ client: SMCClient, deadline: Double) -> [SMCSensorReading.Fan] {
        guard let count = client.value("FNum"), (0...10).contains(count), count.rounded() == count else { return [] }
        var result: [SMCSensorReading.Fan] = []
        for index in 0..<Int(count) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            let mode = client.value("F\(index)Md").flatMap { value -> Int? in
                guard (0...255).contains(value), value.rounded() == value else { return nil }
                return Int(value)
            }
            result.append(SMCSensorReading.Fan(
                index: index, currentRPM: SMCSensorReading.fanRPM(client.value("F\(index)Ac")),
                minimumRPM: SMCSensorReading.fanRPM(client.value("F\(index)Mn")),
                maximumRPM: SMCSensorReading.fanRPM(client.value("F\(index)Mx")), mode: mode))
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
