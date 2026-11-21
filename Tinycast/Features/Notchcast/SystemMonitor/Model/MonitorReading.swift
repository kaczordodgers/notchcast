// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's SystemMonitor, MetricFormat and DiskSupport: the counters and their maths.

import Foundation

/// One raw read of the Mac, every counter cumulative; nil where the read failed or was not asked for.
struct MonitorReading: Equatable, Sendable {
    /// Seconds on the uptime clock, which stops while the Mac sleeps, so a sleep is never a long sample.
    var uptime: TimeInterval
    var cpu: MonitorCPUTicks?
    var memory: MonitorMemory?
    var pressure: MonitorPressure = .unknown
    var disk: MonitorDisk?
    var volumes: [MonitorVolume]?
    var network: MonitorNetworkCounters?
    /// Read only while the page shows, since it walks every process.
    var processes: [MonitorProcessTime]?
}

struct MonitorCPUTicks: Equatable, Sendable {
    var busy: UInt64
    var total: UInt64

    /// user + system + nice over all four, as `host_statistics(HOST_CPU_LOAD_INFO)` counts them.
    init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        busy = user + system + nice
        total = busy + idle
    }

    /// The share of the Mac busy between two reads, 0...1; nil when the counters did not move forward.
    func load(since previous: MonitorCPUTicks) -> Double? {
        guard total > previous.total, busy >= previous.busy else { return nil }
        return min(1, Double(busy - previous.busy) / Double(total - previous.total))
    }
}

struct MonitorMemory: Equatable, Sendable {
    var used: UInt64
    var total: UInt64

    var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }

    /// Activity Monitor's Memory Used: app memory (internal less purgeable) + wired + compressed.
    init?(total: UInt64, pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
          compressorPages: UInt64) {
        guard total > 0, pageSize > 0, internalPages >= purgeablePages else { return nil }
        let pages = (internalPages - purgeablePages).addingReportingOverflow(wiredPages)
        let all = pages.partialValue.addingReportingOverflow(compressorPages)
        let bytes = all.partialValue.multipliedReportingOverflow(by: pageSize)
        guard !pages.overflow, !all.overflow, !bytes.overflow else { return nil }
        used = min(bytes.partialValue, total)
        self.total = total
    }

    init(used: UInt64, total: UInt64) {
        self.used = min(used, total)
        self.total = total
    }
}

/// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
enum MonitorPressure: Equatable, Sendable {
    case normal, warning, critical, unknown

    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

/// The startup volume; free counts what the system would purge to make room, never less than raw free.
struct MonitorDisk: Equatable, Sendable {
    var free: UInt64
    var total: UInt64

    init?(total: UInt64?, rawFree: UInt64?, importantFree: UInt64?) {
        guard let total, total > 0, rawFree != nil || importantFree != nil else { return nil }
        free = min(total, max(rawFree ?? 0, importantFree ?? 0))
        self.total = total
    }

    var used: UInt64 { total - free }
    var fraction: Double { Double(used) / Double(total) }
    var freeFraction: Double { Double(free) / Double(total) }
}

/// Bytes in and out summed over the physical interfaces, with their names so a change resets the rate.
struct MonitorNetworkCounters: Equatable, Sendable {
    var received: UInt64
    var sent: UInt64
    var interfaces: Set<String>

    /// Loopback and virtual interfaces would count a VPN's traffic twice; `feth` pairs mirror each other.
    static func counts(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let excluded = ["lo", "gif", "stf", "awdl", "llw", "nan", "utun", "bridge", "ap", "anpi", "p2p", "XHC",
                        "vmenet", "tap", "tun", "feth"]
        return !excluded.contains { name.hasPrefix($0) }
    }
}

/// A process's cumulative CPU time and its footprint now, read without root; named only if it may be listed.
struct MonitorProcessTime: Equatable, Sendable {
    var pid: Int32
    var name: String?
    var cpuNanoseconds: UInt64
    var footprint: UInt64
}
