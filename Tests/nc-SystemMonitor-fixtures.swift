import Foundation

/// Readings of a made-up Mac: 16 GiB of memory, a 500 GB disk, two busy processes.
enum MonitorFixtures {
    static let gib: UInt64 = 1 << 30
    static let gb: UInt64 = 1_000_000_000
    static let locale = Locale(identifier: "en_US")

    static func disk(freePercent: UInt64) -> MonitorDisk {
        MonitorDisk(total: 500 * gb, rawFree: 5 * gb * freePercent, importantFree: nil)!
    }

    static func volume(_ name: String, path: String? = nil, size: UInt64 = 500 * gb) -> MonitorVolume {
        MonitorVolume(path: path ?? "/Volumes/\(name)", name: name, size: size, isInternal: false, isLocal: true)
    }

    static func process(_ pid: Int32, _ name: String, seconds: Double, footprint: UInt64) -> MonitorProcessTime {
        MonitorProcessTime(pid: pid, name: name, cpuNanoseconds: UInt64(seconds * 1_000_000_000), footprint: footprint)
    }

    static func reading(at uptime: TimeInterval, busy: UInt64, total: UInt64, received: UInt64, sent: UInt64,
                        detail: Bool, pressure: MonitorPressure = .normal, freePercent: UInt64 = 20,
                        step: Double = 1, volumes: [MonitorVolume] = []) -> MonitorReading {
        MonitorReading(
            uptime: uptime, cpu: MonitorCPUTicks(user: busy, system: 0, idle: total - busy, nice: 0),
            memory: MonitorMemory(used: 8 * gib, total: 16 * gib), pressure: pressure,
            disk: disk(freePercent: freePercent), volumes: detail ? volumes : nil,
            network: detail ? MonitorNetworkCounters(received: received, sent: sent, interfaces: ["en0"]) : nil,
            processes: detail ? [
                process(1, "Xcode", seconds: 2 * step, footprint: 2 * gib),
                process(2, "Safari", seconds: 0.8 * step, footprint: gib),
            ] : nil)
    }

    /// Two reads 2 s apart (a third `hotFor` seconds later), so every rate has its baseline.
    static func board(cpu: Double = 0.43, pressure: MonitorPressure = .normal, freePercent: UInt64 = 20,
                      hotFor: TimeInterval = 0, volumes: [MonitorVolume] = []) -> MonitorBoard {
        var board = MonitorBoard()
        let busy = UInt64(cpu * 1000)
        let times: [TimeInterval] = hotFor > 0 ? [0, 2, 2 + hotFor] : [0, 2]
        for (index, time) in times.enumerated() {
            let step = UInt64(index)
            board.apply(reading(at: time, busy: busy * step, total: 1000 * step + 1000, received: 4_000_000 * step,
                                sent: 1_000_000 * step, detail: true, pressure: pressure, freePercent: freePercent,
                                step: Double(index), volumes: volumes), processorCount: 4, locale: locale)
        }
        return board
    }
}
