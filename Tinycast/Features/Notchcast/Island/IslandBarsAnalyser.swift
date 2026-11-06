import Foundation

// Damian Tools' closed-strip bars, ported from Damian's own code (`native/app/Notch/NotchBars.swift`): a Winamp
// spectrum analyser's dynamics on made-up levels. On a scale of 15 rows a bar falls 12/16 of a row per 1/60 s
// step, so it falls a steady 3 heights a second whatever the frame rate; a peak falls 3/256 of a row on its first
// step and 1.1 times further on each step after, so it hangs and then drops. A bar jumps to a new level at once.
// Nothing ticks between readings: each reading gives every bar a trajectory that Core Animation plays.

/// One reading for every bar, 0 to 1, low bands first. `peaks` is where each band reached now, nil for a band that
/// did not move; `rest` is where it settles once its bar has fallen.
struct IslandLevelReading: Equatable {
    var peaks: [Double?]
    var rest: [Double]
}

/// Where the bars' levels come from. Synthetic today; real levels can replace it without touching the view.
@MainActor
protocol IslandLevelSource: AnyObject {
    func start(bars: Int, deliver: @escaping (IslandLevelReading) -> Void)
    func stop()
    var isRunning: Bool { get }
}

/// Winamp's analyser, solved in closed form so it can be played without a frame clock.
struct IslandBarsAnalyser {
    static let stepsPerSecond: Double = 60
    static let rows: Double = 15
    static let fallPerStep: Double = (12.0 / 16.0) / rows
    static var fallPerSecond: Double { fallPerStep * stepsPerSecond }
    static let peakFirstStep: Double = (3.0 / 256.0) / rows
    static let peakAcceleration: Double = 1.1
    /// A peak shows only once it is a row up.
    static let peakVisibleFrom: Double = 1 / rows

    private struct Bar {
        var height: Double = 0
        var rest: Double = 0
        var since: TimeInterval = 0
        var peak: Double = 0
        var peakSince: TimeInterval = 0
    }
    private var bars: [Bar]

    init(bars: Int) { self.bars = Array(repeating: Bar(), count: max(1, bars)) }

    var count: Int { bars.count }

    func height(_ index: Int, at time: TimeInterval) -> Double {
        let bar = bars[index]
        return max(bar.rest, bar.height - Self.fallPerSecond * max(0, time - bar.since))
    }

    func settles(_ index: Int) -> TimeInterval {
        let bar = bars[index]
        return bar.since + max(0, bar.height - bar.rest) / Self.fallPerSecond
    }

    static func peakDrop(steps: Int) -> Double {
        guard steps > 0 else { return 0 }
        return peakFirstStep * (pow(peakAcceleration, Double(steps)) - 1) / (peakAcceleration - 1)
    }

    func peak(_ index: Int, at time: TimeInterval) -> Double {
        let bar = bars[index]
        let steps = Int(max(0, time - bar.peakSince) * Self.stepsPerSecond)
        return max(height(index, at: time), bar.peak - Self.peakDrop(steps: steps))
    }

    mutating func receive(_ reading: IslandLevelReading, at time: TimeInterval) {
        for index in bars.indices {
            let current = height(index, at: time)
            let currentPeak = peak(index, at: time)
            let peak = index < reading.peaks.count ? reading.peaks[index].map(Self.clamped) : nil
            let rest = index < reading.rest.count ? Self.clamped(reading.rest[index]) : bars[index].rest
            let level = max(current, peak ?? 0, rest)
            bars[index].height = level
            bars[index].rest = min(rest, level)
            bars[index].since = time
            if level >= currentPeak - 1e-9 {
                bars[index].peak = level
                bars[index].peakSince = time
            }
        }
    }

    mutating func reset() { bars = Array(repeating: Bar(), count: bars.count) }

    func barTrajectory(_ index: Int, from time: TimeInterval) -> (values: [Double], keyTimes: [Double], duration: TimeInterval) {
        let start = height(index, at: time)
        let end = bars[index].rest
        let length = max(0, start - end) / Self.fallPerSecond
        return length > 0 ? ([start, end], [0, 1], length) : ([end], [0], 0)
    }

    /// The peak's motion from `time`, sampled every other step: exact at each sample.
    func peakTrajectory(_ index: Int, from time: TimeInterval) -> (values: [Double], keyTimes: [Double], duration: TimeInterval) {
        var times: [TimeInterval] = [time]
        var values: [Double] = [peak(index, at: time)]
        let settled = settles(index)
        var moment = time
        while moment < time + 2 {
            moment += 2 / Self.stepsPerSecond
            let value = peak(index, at: moment)
            times.append(moment)
            values.append(value)
            if moment >= settled, abs(value - height(index, at: moment)) < 1e-9 { break }
        }
        let length = (times.last ?? time) - time
        guard length > 0 else { return ([values[0]], [0], 0) }
        return (values, times.map { ($0 - time) / length }, length)
    }

    private static func clamped(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

/// Made-up levels that move like music: irregular impulses 6 to 12 times a second, stronger on a slower beat, the
/// low bands hit harder and more often.
@MainActor
final class IslandSyntheticLevels: IslandLevelSource {
    static let intervalRange: ClosedRange<TimeInterval> = (1.0 / 12)...(1.0 / 6)
    private var random: IslandRandom
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let clock: () -> TimeInterval
    private var generation = 0
    private var deliver: ((IslandLevelReading) -> Void)?
    private var bars = 7
    private var beatStart: TimeInterval = 0
    private var beatPeriod: TimeInterval = 0.5
    private(set) var isRunning = false
    private(set) var deliveries = 0

    init(seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
             Task { @MainActor in
                 try? await Task.sleep(for: .seconds(delay))
                 work()
             }
         }) {
        random = IslandRandom(seed: seed)
        self.clock = clock
        self.schedule = schedule
    }

    func start(bars: Int, deliver: @escaping (IslandLevelReading) -> Void) {
        stop()
        self.bars = max(1, bars)
        self.deliver = deliver
        isRunning = true
        deliveries = 0
        beatStart = clock()
        beatPeriod = 60 / random.uniform(105...135)
        fire()
    }

    func stop() {
        generation += 1
        isRunning = false
        deliver = nil
    }

    private func fire() {
        guard isRunning, let deliver else { return }
        deliveries += 1
        deliver(reading(at: clock()))
        let requested = generation
        schedule(nextInterval()) { [weak self] in
            guard let self, self.generation == requested else { return }
            self.fire()
        }
    }

    func nextInterval() -> TimeInterval {
        let first = random.uniform(Self.intervalRange), second = random.uniform(Self.intervalRange)
        return (first + second) / 2
    }

    func beat(at time: TimeInterval) -> Double {
        let phase = ((time - beatStart) / beatPeriod).truncatingRemainder(dividingBy: 1)
        return 0.45 + 0.55 * pow(1 - phase, 3)
    }

    func reading(at time: TimeInterval) -> IslandLevelReading {
        let beat = beat(at: time)
        var peaks: [Double?] = []
        var rest: [Double] = []
        for index in 0..<bars {
            let low = bars > 1 ? 1 - Double(index) / Double(bars - 1) : 1
            let weight = 0.5 + 0.5 * low
            let hitChance = 0.45 + 0.4 * low * beat + 0.1
            let hit = random.uniform(0...1) < hitChance
            peaks.append(hit ? min(1, weight * beat * random.uniform(0.6...1.05)) : nil)
            rest.append(weight * (0.16 + 0.32 * beat * random.uniform(0.5...1)))
        }
        return IslandLevelReading(peaks: peaks, rest: rest)
    }
}

/// A small seeded generator (SplitMix64), so renders and tests repeat exactly.
struct IslandRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * Double(next() >> 11) / Double(1 << 53)
    }
}
