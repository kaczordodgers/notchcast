import Foundation

/// Rankings cover accessible current-user processes; macOS may deny other users' counters.
nonisolated struct ProcessReading: Sendable, Equatable {
    struct Identity: Sendable, Hashable {
        let pid: Int32
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    struct Counter: Sendable, Equatable {
        let identity: Identity
        let name: String
        let cpuTicks: UInt64
        let residentBytes: UInt64
        let sampledAt: Double
    }

    struct Usage: Sendable, Equatable {
        let identity: Identity
        let name: String
        let cpuPercent: Double?
        let residentBytes: UInt64
    }

    let topCPU: [Usage]
    let topMemory: [Usage]

    static func ranked(current: [Counter], previous: [Identity: Counter],
                       timebaseNumerator: UInt32, timebaseDenominator: UInt32, limit: Int) -> Self {
        guard limit > 0 else { return Self(topCPU: [], topMemory: []) }
        let rows = current.map { counter in
            Usage(identity: counter.identity, name: counter.name,
                  cpuPercent: percentage(counter, previous: previous[counter.identity],
                                         numerator: timebaseNumerator, denominator: timebaseDenominator),
                  residentBytes: counter.residentBytes)
        }
        let cpu = rows.filter { $0.cpuPercent != nil }.sorted {
            if $0.cpuPercent != $1.cpuPercent { return ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
            if $0.residentBytes != $1.residentBytes { return $0.residentBytes > $1.residentBytes }
            return $0.identity.pid < $1.identity.pid
        }
        let memory = rows.sorted {
            if $0.residentBytes != $1.residentBytes { return $0.residentBytes > $1.residentBytes }
            return $0.identity.pid < $1.identity.pid
        }
        return Self(topCPU: Array(cpu.prefix(limit)), topMemory: Array(memory.prefix(limit)))
    }

    private static func percentage(_ current: Counter, previous: Counter?,
                                   numerator: UInt32, denominator: UInt32) -> Double? {
        guard let previous, previous.identity == current.identity, current.cpuTicks >= previous.cpuTicks,
              current.sampledAt.isFinite, previous.sampledAt.isFinite,
              current.sampledAt > previous.sampledAt, numerator > 0, denominator > 0 else { return nil }
        let nanoseconds = Double(current.cpuTicks - previous.cpuTicks) * Double(numerator) / Double(denominator)
        let value = nanoseconds / (current.sampledAt - previous.sampledAt) / 1_000_000_000 * 100
        return value.isFinite ? value : nil
    }
}
