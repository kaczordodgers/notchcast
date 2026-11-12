import Darwin
import Foundation

@main
@MainActor
struct SystemMonitorCPUTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func near(_ actual: Double?, _ expected: Double) -> Bool {
        actual.map { abs($0 - expected) < 0.000_001 } ?? false
    }

    static func main() {
        decoders()
        wire()
        sensors()
        cpuDeltas()
        processes()
        live()
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func decoders() {
        func decode(_ type: String, _ bytes: [UInt8], size: Int? = nil) -> Double? {
            SMCValue(info: .init(size: size ?? bytes.count, type: type, attributes: 0), bytes: bytes).number
        }
        expect(decode("flt ", [0, 0, 0x48, 0x42]) == 50, "SMC float is little endian")
        expect(decode("flt ", [0, 0, 0x20, 0xc1]) == -10, "negative float")
        expect(decode("flt ", [0, 0, 0x80, 0x7f]) == nil, "infinite float rejected")
        expect(decode("flt ", [0, 0, 0xc0, 0x7f]) == nil, "NaN rejected")
        expect(decode("fpe2", [0x1f, 0x42]) == 2000.5, "fan fixed point")
        expect(decode("sp78", [0x32, 0x80]) == 50.5, "signed temperature fixed point")
        expect(decode("sp78", [0xf5, 0x80]) == -10.5, "negative fixed point")
        expect(decode("sp78", [0x80, 0]) == -128, "fixed point lower boundary")
        expect(decode("ui8 ", [255]) == 255, "unsigned byte")
        expect(decode("ui16", [0x12, 0x34]) == 4660, "unsigned short is big endian")
        expect(decode("ui32", [255, 255, 255, 255]) == Double(UInt32.max), "unsigned integer")
        expect(decode("si8 ", [0x80]) == -128, "signed byte")
        expect(decode("si8 ", [127]) == 127, "signed byte upper boundary")
        expect(decode("si16", [0xff, 0xfe]) == -2, "signed short")
        expect(decode("si16", [0x7f, 0xff]) == 32767, "signed short upper boundary")
        expect(decode("ui32", [1, 2], size: 4) == nil, "truncated value")
        expect(decode("ui16", [1]) == nil, "type size mismatch")
        expect(decode("ch8*", [1, 2, 3, 4]) == nil, "unsupported encoding")
        expect(decode("ui8 ", []) == nil, "empty payload")
        expect(decode("flt ", Array(repeating: 255, count: 32)) == nil, "oversized scalar rejected")
    }

    static func wire() {
        expect(SMCWire.code("F0Ac") == 0x46304163, "four character key")
        expect(SMCWire.code("bad") == nil, "short key rejected")
        expect(SMCWire.code("abcde") == nil, "long key rejected")
        expect(SMCWire.code("éab") == nil, "non ASCII key rejected")
        expect(SMCWire.request(.read, size: -1) == nil, "negative payload rejected")
        expect(SMCWire.request(.read, size: 33) == nil, "oversized payload rejected")
        guard let request = SMCWire.request(.read, key: 0x46304163, size: 4),
              var reply = SMCWire.request(.keyInfo) else {
            expect(false, "wire construction")
            return
        }
        expect(request.count == 80 && request[42] == 5, "read wire shape")
        expect(Array(request[0..<4]) == [0x63, 0x41, 0x30, 0x46], "wire key host byte order")
        expect(request[28] == 4 && request[48...].allSatisfy { $0 == 0 }, "read has no payload")
        let indexRequest = SMCWire.request(.keyAtIndex, index: 0x1234)
        expect(indexRequest?[42] == 8 && indexRequest?[44] == 0x34 && indexRequest?[45] == 0x12,
               "index command and offset")
        reply[28] = 4
        reply.replaceSubrange(32..<36, with: [0x20, 0x74, 0x6c, 0x66])
        reply[36] = 0x80
        expect(SMCWire.keyInfo(reply) == .init(size: 4, type: "flt ", attributes: 0x80), "key metadata")
        reply[40] = 0x84
        expect(SMCWire.keyInfo(reply) == nil && !SMCWire.succeeded(reply), "missing key")
        reply[40] = 1
        expect(SMCWire.key(reply) == nil, "driver error rejected")
        reply[40] = 0
        reply[28] = 33
        expect(SMCWire.keyInfo(reply) == nil, "oversized driver payload")
        reply[28] = 0
        expect(SMCWire.keyInfo(reply) == nil, "zero driver payload")
        expect(SMCWire.keyInfo(Array(reply.prefix(79))) == nil, "short driver reply")
        expect(SMCWire.keyInfo(reply + [0]) == nil, "long driver reply")
        expect(SMCWire.key(request) == "F0Ac", "index result decodes key")
        reply[0] = 255
        expect(SMCWire.key(reply) == nil, "non ASCII driver key rejected")
    }

    static func sensors() {
        let dump: [String: Double] = [
            "Te0a": 53.64, "Te0b": 53.64, "Te0x": 56.98, "Te0z": 56.98,
            "Te3a": 55.35, "Te3b": 64.05, "Te3x": 60.81, "Te3z": 80.81,
            "Tp2a": 62.63, "Tp2b": 71.73, "Tp2x": 74.42, "Tp2z": 89.42,
            "Tp9a": 58.78, "Tp9b": 68.88, "Tp9x": 71.53, "Tp9z": 88.53
        ]
        let raw = dump.filter { TemperatureSensorPolicy.isCPUKey($0.key, includesTf: false) }
        expect(raw.count == 8 && raw.keys.allSatisfy { $0.hasSuffix("a") || $0.hasSuffix("x") },
               "key dump excludes derived b/z sensors")
        let expected = (53.64 + 56.98 + 55.35 + 60.81 + 62.63 + 74.42 + 58.78 + 71.53) / 8
        expect(near(TemperatureSensorPolicy.average(Array(raw.values)), expected), "raw die average")
        let fixed = TemperatureSensorPolicy.cpuKeys(brand: "Apple M1").compactMap { dump[$0] }
        expect(near(TemperatureSensorPolicy.average(fixed), expected), "M1 fixed keys match raw dump average")
        expect(!TemperatureSensorPolicy.isCPUKey("Tp2z", includesTf: false)
               && !TemperatureSensorPolicy.isCPUKey("Tp2b", includesTf: false), "derived keys rejected")
        let fixture = ["Tp0b": 65.0, "Tp2z": 90.0, "Tp2b": 80.0]
        for brand in ["Apple M1 Pro", "Apple M1 Max", "Apple M1 Ultra", "Apple M2", "Apple M4"] {
            let readings = SMCSensorReader.temperatures(TemperatureSensorPolicy.cpuKeys(brand: brand),
                                                       deadline: .infinity, value: { fixture[$0] })
            expect(readings == [65], "fixed table uses Tp0b for \(brand)")
        }
        let discovered = ["Tp2z", "Tp2b"].filter {
            TemperatureSensorPolicy.isCPUKey($0, includesTf: false)
        }
        expect(SMCSensorReader.temperatures(discovered, deadline: .infinity,
                                          value: { fixture[$0] }).isEmpty, "discovery ignores derived b/z")
        expect(TemperatureSensorPolicy.hottest([20, 55, 40]) == 55, "hottest valid sensor")
        expect(TemperatureSensorPolicy.hottest([9.9, 125, .nan, .infinity, -1]) == nil, "implausible sensors")
        expect(TemperatureSensorPolicy.hottest([10, 124.9, 400]) == 124.9, "temperature boundaries")
        expect(TemperatureSensorPolicy.hottest([]) == nil, "no sensor")
        let mapped: [(String, String)] = [
            ("Apple M1 Max", "Tp0T"), ("Apple M2 Pro", "Tp1h"), ("Apple M3 Max", "Tf4E"),
            ("Apple M4", "Tp0V"), ("Apple M4 Pro", "Tex0"), ("Apple M5", "Tp0u")
        ]
        for (brand, key) in mapped {
            let keys = TemperatureSensorPolicy.cpuKeys(brand: brand)
            expect(keys.contains(key), "mapped sensor for \(brand)")
            expect(Set(keys).count == keys.count && keys.allSatisfy { SMCWire.code($0) != nil }, "valid unique sensor keys")
        }
        expect(TemperatureSensorPolicy.cpuKeys(brand: "Apple M10") == TemperatureSensorPolicy.fallbackCPUKeys,
               "unknown chip uses known CPU families")
        expect(TemperatureSensorPolicy.isCPUKey("Tp2a", includesTf: false), "unmapped performance sensor")
        expect(TemperatureSensorPolicy.isCPUKey("Te0a", includesTf: false), "unmapped efficiency sensor")
        expect(!TemperatureSensorPolicy.isCPUKey("TB0T", includesTf: true), "battery is not a CPU sensor")
        expect(!TemperatureSensorPolicy.isCPUKey("Tp123", includesTf: true), "sensor keys have four characters")
        expect(TemperatureSensorPolicy.isCPUKey("Tf4E", includesTf: true)
               && !TemperatureSensorPolicy.isCPUKey("Tf4E", includesTf: false), "Tf restricted to mapped chips")
        expect(TemperatureSensorPolicy.isGPUKey("Tg1b") && !TemperatureSensorPolicy.isGPUKey("Tp2a"),
               "unmapped GPU sensor family")
        expect(SMCSensorReading.fanRPM(0) == 0, "stopped fan is valid")
        expect(SMCSensorReading.fanRPM(-1) == nil && SMCSensorReading.fanRPM(.nan) == nil, "invalid fan")
        expect(SMCSensorReading.fanRPM(40_000) == nil, "implausible fan")
        expect(SMCSensorReading.powerWatts(42.5) == 42.5, "power in watts")
        expect(SMCSensorReading.powerWatts(-1) == nil && SMCSensorReading.powerWatts(.infinity) == nil, "invalid power")
        expect(SMCSensorReading.powerWatts(nil) == nil, "missing power")
        var unavailable = SMCSensorReader(client: nil, brand: "Apple M4")
        expect(unavailable.read()
               == SMCSensorReading(cpuTemperature: nil, gpuTemperature: nil, systemPowerWatts: nil, fans: []),
               "unavailable SMC returns absent readings")
    }

    static func cpuDeltas() {
        let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 20, system: 10, idle: 60, nice: 10)
        let usage = current.delta(since: zero)?.usage
        expect(near(usage?.totalPercent, 40), "CPU total")
        expect(near(usage?.userPercent, 30), "nice counts as user")
        expect(near(usage?.systemPercent, 10), "system CPU")
        expect(zero.delta(since: zero)?.usage == nil, "no ticks yields unknown usage")
        let beforeWrap = CPUTicks(user: .max - 4, system: .max - 2, idle: .max - 8, nice: .max)
        let afterWrap = CPUTicks(user: 5, system: 2, idle: 6, nice: 4)
        let wrapped = afterWrap.delta(since: beforeWrap)
        expect(wrapped == CPUTicks.Delta(user: 15, system: 5, idle: 15), "independent 32 bit rollovers")
        expect(near(wrapped?.usage?.totalPercent, 100 * 20 / 35), "usage survives rollover")
        expect(zero.delta(since: current) == nil, "counter reset yields unknown")
        let mixed = CPUTicks.usage(current: [current, CPUTicks(user: 0, system: 0, idle: 300, nice: 0)],
                                   previous: [zero, zero])
        expect(near(mixed.total?.totalPercent, 10), "machine usage weights ticks across cores")
        expect(near(mixed.cores[0]?.totalPercent, 40) && mixed.cores[1]?.totalPercent == 0, "per core usage")
        let changed = CPUTicks.usage(current: [current], previous: [zero, zero])
        expect(changed.total == nil && changed.cores == [nil], "changed core count resets baseline")
        let reset = CPUTicks.usage(current: [zero, current], previous: [current, zero])
        expect(reset.total == nil && reset.cores[0] == nil && reset.cores[1] != nil, "one reset invalidates aggregate")
    }

    static func processes() {
        func counter(_ pid: Int32, start: UInt64 = 1, ticks: UInt64, bytes: UInt64,
                     time: Double) -> ProcessReading.Counter {
            .init(identity: .init(pid: pid, startSeconds: start, startMicroseconds: 12),
                  name: "process-\(pid)", cpuTicks: ticks, residentBytes: bytes, sampledAt: time)
        }
        func rank(_ current: [ProcessReading.Counter], _ old: [ProcessReading.Counter], limit: Int = 5,
                  numerator: UInt32 = 1, denominator: UInt32 = 1) -> ProcessReading {
            .ranked(current: current, previous: Dictionary(uniqueKeysWithValues: old.map { ($0.identity, $0) }),
                    timebaseNumerator: numerator, timebaseDenominator: denominator, limit: limit)
        }
        let old = [counter(1, ticks: 0, bytes: 100, time: 10), counter(2, ticks: 0, bytes: 500, time: 10)]
        let current = [counter(1, ticks: 4_000_000_000, bytes: 100, time: 12),
                       counter(2, ticks: 1_000_000_000, bytes: 500, time: 12)]
        let reading = rank(current, old)
        expect(reading.topCPU.map(\.identity.pid) == [1, 2], "rank by CPU")
        expect(reading.topMemory.map(\.identity.pid) == [2, 1], "rank by resident memory")
        expect(near(reading.topCPU.first?.cpuPercent, 200), "process may occupy multiple cores")
        expect(near(reading.topCPU.last?.cpuPercent, 50), "process CPU interval")
        expect(reading.topMemory.first?.residentBytes == 500, "resident bytes unchanged")
        expect(reading.topCPU.first?.name == "process-1", "process name retained")
        expect(rank(current, old, limit: 1).topCPU.count == 1, "CPU limit")
        expect(rank(current, old, limit: 1).topMemory.count == 1, "memory limit")
        expect(rank(current, old, limit: -1) == ProcessReading(topCPU: [], topMemory: []), "negative limit")
        let first = rank(current, [])
        expect(first.topCPU.isEmpty && first.topMemory.allSatisfy { $0.cpuPercent == nil }, "first sample baseline")
        let reused = rank([counter(1, start: 2, ticks: 8_000_000_000, bytes: 200, time: 12)], old)
        expect(reused.topCPU.isEmpty && reused.topMemory.first?.cpuPercent == nil, "PID reuse is not CPU delta")
        let sameSecond = ProcessReading.Counter(
            identity: .init(pid: 1, startSeconds: 1, startMicroseconds: 13), name: "replacement",
            cpuTicks: 8_000_000_000, residentBytes: 200, sampledAt: 12)
        expect(rank([sameSecond], old).topCPU.isEmpty, "subsecond PID reuse is distinct")
        let reset = rank([counter(1, ticks: 0, bytes: 100, time: 14)], current)
        expect(reset.topCPU.isEmpty, "process counter regression")
        expect(rank(old, old).topCPU.isEmpty, "zero elapsed interval")
        expect(rank(old, current).topCPU.isEmpty, "backwards clock")
        expect(rank(current, old, denominator: 0).topCPU.isEmpty, "invalid timebase")
        expect(near(rank(current, old, numerator: 125, denominator: 3).topCPU.first?.cpuPercent,
                    200 * 125 / 3), "Mach ticks use complete timebase ratio")
        let tied = [counter(2, ticks: 0, bytes: 100, time: 12), counter(1, ticks: 0, bytes: 100, time: 12)]
        expect(rank(tied, old).topMemory.map(\.identity.pid) == [1, 2], "deterministic ties")
        expect(rank([], current).topCPU.isEmpty, "exited processes disappear")
    }

    static func live() {
        var cpu = CPUSampler()
        let baseline = cpu.sample()
        expect(baseline.usage == nil && baseline.cores.allSatisfy { $0 == nil }, "live CPU warms up")
        var processes = ProcessSampler()
        let processBaseline = processes.sample(limit: 3)
        expect(processBaseline.topCPU.isEmpty && processBaseline.topMemory.count <= 3, "live process baseline")
        let client = SMCClient()
        expect(client?.read("bad") == nil && client?.keyInfo("abcde") == nil, "live client rejects malformed keys")
        let keys = client?.keys(limit: 2) ?? []
        expect(keys.count <= 2 && keys.allSatisfy { $0.utf8.count == 4 }, "live key enumeration shape")
        let sensorStart = ProcessInfo.processInfo.systemUptime
        var sensorReader = SMCSensorReader(client: client)
        var sensors = sensorReader.read()
        let sensorMilliseconds = (ProcessInfo.processInfo.systemUptime - sensorStart) * 1_000
        expect(sensors.cpuTemperature.map { (10..<125).contains($0) } ?? true, "live CPU temperature or nil")
        expect(sensors.gpuTemperature.map { (10..<125).contains($0) } ?? true, "live GPU temperature or nil")
        expect(sensors.systemPowerWatts.map { (0...2_000).contains($0) } ?? true, "live power or nil")
        expect(sensors.fans.count <= 10 && sensors.fans.allSatisfy {
            $0.currentRPM.map { (0...30_000).contains($0) } ?? true
        }, "live fans shape")
        Thread.sleep(forTimeInterval: 0.2)
        let nextSensorStart = ProcessInfo.processInfo.systemUptime
        sensors = sensorReader.read()
        var nextSensorMilliseconds = (ProcessInfo.processInfo.systemUptime - nextSensorStart) * 1_000
        for _ in 0..<12 {
            let start = ProcessInfo.processInfo.systemUptime
            sensors = sensorReader.read()
            nextSensorMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        }
        let rawKeys = TemperatureSensorPolicy.cpuKeys(brand: "Apple M1")
        let rawAverage = TemperatureSensorPolicy.average(rawKeys.compactMap { client?.value($0) })
        let reference = rawAverage.map { String(format: "%.1f", $0) } ?? "nil"
        let reading = cpu.sample()
        expect(reading.usage.map { $0.totalPercent >= 0 && $0.totalPercent <= 100.000_001 } ?? true, "live CPU range")
        expect(reading.cores.count == baseline.cores.count, "live core shape")
        expect(reading.loadAverage.map { $0.oneMinute >= 0 && $0.fiveMinutes >= 0 && $0.fifteenMinutes >= 0 } ?? true,
               "live load averages")
        let rows = processes.sample(limit: 3)
        expect(rows.topCPU.count <= 3 && rows.topMemory.count <= 3, "live process limits")
        expect(rows.topCPU.allSatisfy { $0.identity.pid > 0 && ($0.cpuPercent?.isFinite ?? false) }, "live process shape")
        cpu.reset()
        processes.reset()
        expect(cpu.sample().usage == nil && processes.sample().topCPU.isEmpty, "service reset clears baselines")
        let percent = reading.usage.map { String(format: "%.1f", $0.totalPercent) } ?? "nil"
        let temperature = sensors.cpuTemperature.map { String(format: "%.1f", $0) } ?? "nil"
        let fans = sensors.fans.map { fan in
            "F\(fan.index):" + (fan.currentRPM.map { String(format: "%.0f", $0) } ?? "nil")
        }.joined(separator: ",")
        let duration = String(format: "%.1f/%.1f", sensorMilliseconds, nextSensorMilliseconds)
        print("LIVE CPU \(percent)% | CPU temp \(temperature) C | raw M1 mean \(reference) C"
              + " | fan RPMs [\(fans)] | SMC initial/steady \(duration) ms")
    }
}
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
