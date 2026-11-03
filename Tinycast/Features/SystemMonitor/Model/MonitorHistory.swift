import Foundation

nonisolated struct MonitorHistory: Sendable, Equatable {
    let capacity: Int
    private var samples: [Double] = []
    private var nextIndex = 0

    init(capacity: Int = 60) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var values: [Double] {
        guard samples.count == capacity else { return samples }
        return Array(samples[nextIndex...] + samples[..<nextIndex])
    }

    var min: Double? { samples.min() }
    var max: Double? { samples.max() }
    var latest: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.count < capacity ? samples.last : samples[(nextIndex + capacity - 1) % capacity]
    }

    mutating func append(_ value: Double) {
        guard value.isFinite else { return }
        if samples.count < capacity {
            samples.append(value)
        } else {
            samples[nextIndex] = value
        }
        nextIndex = (nextIndex + 1) % capacity
    }

    mutating func clear() {
        samples.removeAll(keepingCapacity: true)
        nextIndex = 0
    }
}
