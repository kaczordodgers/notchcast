import Foundation

struct RecordingTimeline: Sendable {
    private(set) var origin: TimeInterval?
    private var pauseStart: TimeInterval?
    private var pauses: [(start: TimeInterval, end: TimeInterval)] = []

    mutating func begin(at time: TimeInterval) {
        guard origin == nil, time.isFinite else { return }
        origin = time
    }

    mutating func setPaused(_ paused: Bool, at time: TimeInterval) {
        guard let origin, time.isFinite, time >= origin else { return }
        if paused {
            if pauseStart == nil { pauseStart = time }
        } else if let start = pauseStart, time >= start {
            pauses.append((start, time))
            pauseStart = nil
        }
    }

    func elapsed(at time: TimeInterval) -> TimeInterval {
        guard let origin, time.isFinite else { return 0 }
        let end = min(time, pauseStart ?? time)
        let removed = pauses.reduce(0) { $0 + max(0, min(end, $1.end) - $1.start) }
        return max(0, end - origin - removed)
    }

    func sampleTime(at time: TimeInterval, duration: TimeInterval) -> TimeInterval? {
        guard let origin, time.isFinite, time >= origin else { return nil }
        let end = time + max(0, duration.isFinite ? duration : 0)
        guard pauseStart.map({ end <= $0 && time < $0 }) ?? true else { return nil }
        guard !pauses.contains(where: { time < $0.end && end > $0.start || time == $0.start }) else { return nil }
        return elapsed(at: time)
    }
}
