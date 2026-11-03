import Foundation

nonisolated struct DiskIOReading: Sendable, Equatable {
    struct Counters: Sendable, Equatable {
        let read: UInt64
        let written: UInt64
    }

    let id: UInt64
    let readBytesPerSecond: Double?
    let writeBytesPerSecond: Double?

    static func rate(current: UInt64, previous: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed.isFinite, elapsed > 0, elapsed <= 15, current >= previous else { return nil }
        return Double(current - previous) / elapsed
    }
}
