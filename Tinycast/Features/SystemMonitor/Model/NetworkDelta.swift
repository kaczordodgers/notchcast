import Foundation

nonisolated struct NetworkDelta: Sendable, Equatable {
    struct Counter: Sendable, Equatable {
        let interface: String
        let received: UInt64
        let sent: UInt64
        let time: TimeInterval
    }

    private var previous: Counter?
    private(set) var totalDown: UInt64 = 0
    private(set) var totalUp: UInt64 = 0

    mutating func update(_ current: Counter?) -> (down: Double?, up: Double?) {
        defer { previous = current }
        guard let current, let previous, current.interface == previous.interface,
              current.time.isFinite, previous.time.isFinite, current.time > previous.time else {
            return (nil, nil)
        }
        let down = current.received >= previous.received ? current.received - previous.received : 0
        let up = current.sent >= previous.sent ? current.sent - previous.sent : 0
        totalDown = Self.add(totalDown, down)
        totalUp = Self.add(totalUp, up)
        let seconds = current.time - previous.time
        return (Double(down) / seconds, Double(up) / seconds)
    }

    private static func add(_ total: UInt64, _ delta: UInt64) -> UInt64 {
        let result = total.addingReportingOverflow(delta)
        return result.overflow ? .max : result.partialValue
    }
}
