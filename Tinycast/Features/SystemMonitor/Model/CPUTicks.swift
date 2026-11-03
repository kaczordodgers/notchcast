// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

nonisolated struct CPUTicks: Sendable, Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    struct Delta: Sendable, Equatable {
        let user: UInt64
        let system: UInt64
        let idle: UInt64

        var usage: CPUReading.Usage? {
            let total = Double(user + system + idle)
            guard total > 0 else { return nil }
            let userPercent = Double(user) / total * 100
            let systemPercent = Double(system) / total * 100
            return CPUReading.Usage(totalPercent: userPercent + systemPercent,
                                    userPercent: userPercent, systemPercent: systemPercent)
        }
    }

    func delta(since previous: Self) -> Delta? {
        let current = [user, system, idle, nice]
        let old = [previous.user, previous.system, previous.idle, previous.nice]
        var deltas: [UInt64] = []
        for (new, before) in zip(current, old) {
            guard new >= before || before - new > UInt32.max / 2 else { return nil }
            deltas.append(UInt64(new &- before))
        }
        return Delta(user: deltas[0] + deltas[3], system: deltas[1], idle: deltas[2])
    }

    static func usage(current: [Self], previous: [Self]) -> (total: CPUReading.Usage?, cores: [CPUReading.Usage?]) {
        guard !current.isEmpty, current.count == previous.count else {
            return (nil, Array(repeating: nil, count: current.count))
        }
        let deltas = zip(current, previous).map { $0.delta(since: $1) }
        let cores = deltas.map { $0?.usage }
        guard deltas.allSatisfy({ $0 != nil }) else { return (nil, cores) }
        let sum = deltas.compactMap { $0 }.reduce(Delta(user: 0, system: 0, idle: 0)) {
            Delta(user: $0.user + $1.user, system: $0.system + $1.system, idle: $0.idle + $1.idle)
        }
        return (sum.usage, cores)
    }
}
