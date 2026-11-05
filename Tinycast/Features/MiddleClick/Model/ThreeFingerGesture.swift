import Foundation

struct TouchPoint: Equatable, Sendable {
    var id: Int32
    var x: Float
    var y: Float
    var down: Bool
}

struct ThreeFingerGesture {
    static let maxDuration: TimeInterval = 0.25
    static let maxTravel: Float = 0.02

    private struct Start {
        let time: TimeInterval
        let positions: [Int32: (x: Float, y: Float)]
    }

    private var start: Start?
    private var spent = false

    private(set) var threeDown = false

    mutating func frame(_ touches: [TouchPoint], at time: TimeInterval) -> Bool {
        let down = touches.filter(\.down)
        threeDown = down.count == 3
        // All three fingers often lift in one frame: judge the tap before the empty frame resets.
        defer {
            if down.isEmpty {
                start = nil
                spent = false
            }
        }
        if down.count > 3 { spent = true }
        guard !spent else { return false }
        if down.count == 3 {
            guard let start else {
                start = Start(time: time, positions: Dictionary(
                    down.map { ($0.id, (x: $0.x, y: $0.y)) }, uniquingKeysWith: { first, _ in first }))
                return false
            }
            if time - start.time > Self.maxDuration || moved(down, from: start) { spent = true }
            return false
        }
        guard let begun = start else { return false }
        start = nil
        spent = true
        return (0...Self.maxDuration).contains(time - begun.time) && !moved(down, from: begun)
    }

    mutating func claimClick() {
        spent = true
    }

    private func moved(_ down: [TouchPoint], from start: Start) -> Bool {
        down.contains { finger in
            guard let origin = start.positions[finger.id] else { return true }
            return hypot(finger.x - origin.x, finger.y - origin.y) > Self.maxTravel
        }
    }
}

enum MiddleClickGuards {
    static let fingerFreshness: TimeInterval = 0.25
    static let minimumSettle: TimeInterval = 0.04
    static let repeatGuard: TimeInterval = 0.30
    static let keyboardIdle: TimeInterval = 0.5

    enum Press: Equatable {
        case middle
        case bounce
        case plain
    }

    static func press(threeDown: Bool, frameAge: TimeInterval, settledFor: TimeInterval,
                      sinceLastMiddle: TimeInterval?) -> Press {
        guard (0...fingerFreshness).contains(frameAge) else { return .plain }
        if threeDown, settledFor >= minimumSettle { return .middle }
        if let sinceLastMiddle, (0..<repeatGuard).contains(sinceLastMiddle) { return .bounce }
        return .plain
    }

    static func tapAllowed(secondsSinceKeyDown: TimeInterval) -> Bool { secondsSinceKeyDown >= keyboardIdle }
}

// The lock owns all gesture state shared by the touch callback and the event tap.
final class ThreeFingerState: @unchecked Sendable {
    private struct Pad {
        var gesture = ThreeFingerGesture()
        var lastFrame: TimeInterval = 0
        var threeSince: TimeInterval?
    }

    private let lock = NSLock()
    private let clock: @Sendable () -> TimeInterval
    private var pads: [Int: Pad] = [:]
    private var lastMiddle: TimeInterval?

    init(clock: @escaping @Sendable () -> TimeInterval) {
        self.clock = clock
    }

    func frame(device: Int, touches: [TouchPoint], at time: TimeInterval) -> Bool {
        lock.withLock {
            let now = clock()
            var pad = pads[device] ?? Pad()
            let tapped = pad.gesture.frame(touches, at: time)
            pad.lastFrame = now
            if !pad.gesture.threeDown {
                pad.threeSince = nil
            } else if pad.threeSince == nil {
                pad.threeSince = now
            }
            pads[device] = pad
            return tapped
        }
    }

    func press() -> MiddleClickGuards.Press {
        lock.withLock {
            let now = clock()
            let newest = pads.values.filter { $0.gesture.threeDown }.map(\.lastFrame).max() ?? -.infinity
            let threePad = pads.filter { $0.value.gesture.threeDown }
                .max { $0.value.lastFrame < $1.value.lastFrame }
            let result = MiddleClickGuards.press(
                threeDown: threePad != nil, frameAge: now - newest,
                settledFor: threePad?.value.threeSince.map { now - $0 } ?? 0, sinceLastMiddle: lastMiddle.map { now - $0 })
            if result != .bounce, let device = threePad?.key { pads[device]?.gesture.claimClick() }
            return result
        }
    }

    func markMiddleClick() { lock.withLock { lastMiddle = clock() } }

    func reset() {
        lock.withLock {
            pads = [:]
            lastMiddle = nil
        }
    }
}
