// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's SystemMonitor, NetworkSampler and ProcessUsageService: rates between reads.

import Foundation

/// A process by its share of the whole Mac's CPU (0...1) between two reads, and its footprint now.
struct MonitorProcess: Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpu: Double
    var footprint: UInt64
}

/// What the page shows: rates between the last two reads, nil until there are two.
struct MonitorSample: Equatable, Sendable {
    var cpu: Double?
    var memory: MonitorMemory?
    var pressure: MonitorPressure = .unknown
    var disk: MonitorDisk?
    var volumes: [MonitorVolume] = []
    var down: Double?
    var up: Double?
    var processes: [MonitorProcess]?
}

/// Turns cumulative reads into rates and keeps the hot state (decision 946: 2 s shown, 15 s for the hot check).
struct MonitorBoard: Sendable {
    static let shownInterval: Duration = .seconds(2)
    /// After a read that only set a baseline, so network and processes show on a short glance.
    static let baselineInterval: Duration = .milliseconds(500)
    static let hiddenInterval: Duration = .seconds(15)
    /// Lets the system batch the hidden wake-up; 15 + 2 s stays under `maxGap`.
    static let hiddenTolerance: Duration = .seconds(2)
    /// Past this the previous read only starts a new baseline, as after a pause; above the hidden interval.
    static let maxGap: TimeInterval = 20
    static let processLimit = 5

    private(set) var sample = MonitorSample()
    private(set) var heat = MonitorHeat()
    var ejecting: Set<String> = []

    mutating func didEject(_ path: String) {
        sample.volumes.removeAll { $0.path == path }
    }
    private var cpu: (ticks: MonitorCPUTicks, at: TimeInterval)?
    private var network: (counters: MonitorNetworkCounters, at: TimeInterval)?
    private var processes: (times: [Int32: UInt64], at: TimeInterval)?
    private var baselineOnly = false

    /// The last read's process times: the next read ranks against them to name only the listed rows.
    var processTimes: [Int32: UInt64] { processes?.times ?? [:] }

    /// How long until the next read; a shown baseline wants its rates soon.
    func interval(shown: Bool) -> Duration {
        guard shown else { return Self.hiddenInterval }
        return baselineOnly ? Self.baselineInterval : Self.shownInterval
    }

    /// The reads a page hides (network, processes) are dropped, so showing it again starts from a fresh baseline.
    mutating func apply(_ reading: MonitorReading, processorCount: Int, locale: Locale) {
        let now = reading.uptime
        var next = MonitorSample(memory: reading.memory, pressure: reading.pressure, disk: reading.disk)
        next.volumes = MonitorVolumes.listed(reading.volumes ?? [], locale: locale)
        if let ticks = reading.cpu {
            if let cpu, now > cpu.at, now - cpu.at <= Self.maxGap { next.cpu = ticks.load(since: cpu.ticks) }
            cpu = (ticks, now)
        } else {
            cpu = nil
        }
        if let counters = reading.network {
            if let network, now > network.at, now - network.at <= Self.maxGap,
               network.counters.interfaces == counters.interfaces {
                let elapsed = now - network.at
                next.down = Double(counters.received >= network.counters.received
                                   ? counters.received - network.counters.received : 0) / elapsed
                next.up = Double(counters.sent >= network.counters.sent
                                 ? counters.sent - network.counters.sent : 0) / elapsed
            }
            network = (counters, now)
        } else {
            network = nil
        }
        if let times = reading.processes {
            if let processes, now > processes.at, now - processes.at <= Self.maxGap {
                next.processes = Self.top(times, since: processes.times, elapsed: now - processes.at,
                                          processorCount: processorCount)
            }
            processes = (Dictionary(times.map { ($0.pid, $0.cpuNanoseconds) }) { first, _ in first }, now)
        } else {
            processes = nil
        }
        baselineOnly = (reading.network != nil && next.down == nil)
            || (reading.processes != nil && next.processes == nil)
        sample = next
        heat.update(cpu: next.cpu, readAt: now, pressure: next.pressure, disk: next.disk)
    }

    /// Busiest first, ties by footprint then pid; a process new since the last read has no share yet.
    static func top(_ times: [MonitorProcessTime], since previous: [Int32: UInt64], elapsed: TimeInterval,
                    processorCount: Int) -> [MonitorProcess] {
        let capacity = elapsed * 1_000_000_000 * Double(max(1, processorCount))
        guard capacity > 0 else { return [] }
        return ranked(times, since: previous).map { process in
            let share = min(1, Double(process.cpuNanoseconds - previous[process.pid, default: 0]) / capacity)
            return MonitorProcess(pid: process.pid, name: process.name ?? "pid \(process.pid)", cpu: share,
                                  footprint: process.footprint)
        }
    }

    /// The rows `top` lists, from the times alone, so a read can name just these before the board ranks them.
    static func ranked(_ times: [MonitorProcessTime], since previous: [Int32: UInt64]) -> [MonitorProcessTime] {
        let rows = times.compactMap { process -> (MonitorProcessTime, UInt64)? in
            guard let before = previous[process.pid], process.cpuNanoseconds >= before else { return nil }
            return (process, process.cpuNanoseconds - before)
        }
        return Array(rows.sorted {
            ($0.1, $0.0.footprint, -$0.0.pid) > ($1.1, $1.0.footprint, -$1.0.pid)
        }.prefix(processLimit).map(\.0))
    }
}
