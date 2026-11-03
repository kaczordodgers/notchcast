import Foundation

struct LowDiskEngine: Sendable {
    struct Space: Sendable, Equatable {
        let free: Int64
        let total: Int64

        var isValid: Bool { total > 0 && free >= 0 && free <= total }
        var fraction: Double { Double(free) / Double(total) }
    }

    private(set) var isLow: Bool
    private(set) var space: Space?

    init(isLow: Bool = false) {
        self.isLow = isLow
    }

    @discardableResult
    mutating func consume(_ next: Space) -> Bool {
        guard next.isValid else { return false }
        space = next
        let wasLow = isLow
        if isLow {
            isLow = !(next.fraction >= 0.15 && next.free >= 45_000_000_000)
        } else {
            isLow = next.fraction < 0.10 || next.free < 30_000_000_000
        }
        return isLow && !wasLow
    }
}
