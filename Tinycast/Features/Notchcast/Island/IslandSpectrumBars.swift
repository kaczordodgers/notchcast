// Damian Tools' closed-strip bars (NotchBars.swift, Damian's own code), restyled with the kit: Winamp's analyser
// dynamics on made-up levels. On a scale of 15 rows a bar falls 12/16 of a row per 1/60 s step; a peak falls 3/256
// of a row on its first step and 1.1 times further on each step after, so it hangs and then drops. A bar jumps to a
// new level at once. Nothing ticks between readings: each reading gives every bar a trajectory Core Animation plays
// in the render server; the synthetic source wakes about eight times a second, only while a playing song shows.
import AppKit
import QuartzCore
import SwiftUI

/// One reading for every bar, 0 to 1, low bands first. `peaks` is where each band reached now, nil for a band that
/// did not move; `rest` is where it settles once its bar has fallen.
struct IslandLevelReading: Equatable {
    var peaks: [Double?]
    var rest: [Double]
}

/// Winamp's analyser, solved in closed form so it can be played without a frame clock.
struct IslandSpectrumAnalyser {
    static let stepsPerSecond: Double = 60
    static let rows: Double = 15
    static let fallPerStep: Double = (12.0 / 16.0) / rows
    static var fallPerSecond: Double { fallPerStep * stepsPerSecond }
    static let peakFirstStep: Double = (3.0 / 256.0) / rows
    static let peakAcceleration: Double = 1.1
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
        let duration = max(0, start - end) / Self.fallPerSecond
        return duration > 0 ? ([start, end], [0, 1], duration) : ([end], [0], 0)
    }

    func peakTrajectory(_ index: Int, from time: TimeInterval) -> (values: [Double], keyTimes: [Double], duration: TimeInterval) {
        var times: [TimeInterval] = [time]
        var values: [Double] = [peak(index, at: time)]
        let settled = settles(index)
        var t = time
        while t < time + 2 {
            t += 2 / Self.stepsPerSecond
            let value = peak(index, at: t)
            times.append(t)
            values.append(value)
            if t >= settled, abs(value - height(index, at: t)) < 1e-9 { break }
        }
        let duration = (times.last ?? time) - time
        guard duration > 0 else { return ([values[0]], [0], 0) }
        return (values, times.map { ($0 - time) / duration }, duration)
    }

    private static func clamped(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

/// Made-up levels that move like music in a Winamp analyser: irregular impulses about eight times a second,
/// stronger on a slower beat, the low bands hit harder and more often.
@MainActor
final class IslandSyntheticLevels {
    static let intervalRange: ClosedRange<TimeInterval> = (1.0 / 12)...(1.0 / 6)
    private var random: IslandRandom
    private var generation = 0
    private var deliver: ((IslandLevelReading) -> Void)?
    private var bars = NotchcastTheme.SpectrumBars.count
    private var beatStart: TimeInterval = 0
    private var beatPeriod: TimeInterval = 0.5
    private(set) var isRunning = false

    init(seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) {
        random = IslandRandom(seed: seed)
    }

    func start(bars: Int, deliver: @escaping (IslandLevelReading) -> Void) {
        stop()
        self.bars = max(1, bars)
        self.deliver = deliver
        isRunning = true
        beatStart = CACurrentMediaTime()
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
        deliver(reading(at: CACurrentMediaTime()))
        let requested = generation
        let interval = nextInterval()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard let self, self.generation == requested else { return }
            self.fire()
        }
    }

    func nextInterval() -> TimeInterval {
        let a = random.uniform(Self.intervalRange), b = random.uniform(Self.intervalRange)
        return (a + b) / 2
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

/// A small seeded generator (SplitMix64), so renders repeat exactly.
struct IslandRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * Double(next() >> 11) / Double(1 << 53)
    }
}

/// The bars on their own layers. Each reading installs one linear fall per bar and a sampled drop per peak.
final class IslandSpectrumBarsView: NSView {
    private var barLayers: [CALayer] = []
    private var peakLayers: [CALayer] = []
    private var analyser = IslandSpectrumAnalyser(bars: NotchcastTheme.SpectrumBars.count)
    private let source = IslandSyntheticLevels()
    private let barWidth = NotchcastTheme.SpectrumBars.width
    private let boxHeight = NotchcastTheme.SpectrumBars.height
    private var playing = false
    private var reduceMotion = false
    /// Forced visibility for an offscreen fixture; nil asks the window.
    var visibleOverride: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        let count = NotchcastTheme.SpectrumBars.count
        barLayers = (0..<count).map { _ in Self.inkLayer() }
        peakLayers = (0..<count).map { _ in Self.inkLayer() }
        (barLayers + peakLayers).forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static var width: CGFloat {
        let count = CGFloat(NotchcastTheme.SpectrumBars.count)
        return NotchcastTheme.SpectrumBars.width * count + NotchcastTheme.SpectrumBars.gap * (count - 1)
    }

    func configure(playing: Bool, reduceMotion: Bool) {
        self.playing = playing
        self.reduceMotion = reduceMotion
        update()
    }

    func stop() {
        playing = false
        update()
    }

    private static func inkLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor(NotchcastTheme.Colors.primary).cgColor  // kit: ok the kit colour, as a CGColor for the layer
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        update()
    }

    override func viewDidHide() { super.viewDidHide(); update() }
    override func viewDidUnhide() { super.viewDidUnhide(); update() }
    override func layout() { super.layout(); update() }

    private var onScreen: Bool {
        visibleOverride ?? (!isHiddenOrHasHiddenAncestor && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true)
    }

    private var maximumBar: CGFloat {
        max(barWidth, boxHeight - NotchcastTheme.SpectrumBars.peakHeight - NotchcastTheme.SpectrumBars.peakGap)
    }

    private func update() {
        let moving = playing && !reduceMotion && onScreen
        if moving {
            guard !source.isRunning else { return }
            source.start(bars: barLayers.count) { [weak self] reading in self?.receive(reading) }
        } else {
            if source.isRunning { source.stop() }
            analyser.reset()
            rest()
        }
    }

    /// Paused, hidden or still: a dot for each bar, no peaks, no animation.
    private func rest() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            bar.removeAllAnimations()
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barWidth)
            bar.position = CGPoint(x: x(index), y: 0)
            bar.cornerRadius = barWidth / 2
            peakLayers[index].removeAllAnimations()
            peakLayers[index].isHidden = true
        }
        CATransaction.commit()
    }

    private func x(_ index: Int) -> CGFloat {
        CGFloat(index) * (barWidth + NotchcastTheme.SpectrumBars.gap) + barWidth / 2
    }

    private func barHeight(_ level: Double) -> CGFloat { max(barWidth, maximumBar * CGFloat(level)) }

    private func receive(_ reading: IslandLevelReading) {
        let now = CACurrentMediaTime()
        analyser.receive(reading, at: now)
        // A still picture renders model values, so a fixture holds the frame the reading starts on.
        let still = visibleOverride != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let fall = analyser.barTrajectory(index, from: now)
            bar.removeAnimation(forKey: "fall")
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth,
                                height: barHeight((still ? fall.values.first : fall.values.last) ?? 0))
            bar.position = CGPoint(x: x(index), y: 0)
            bar.cornerRadius = barWidth / 2
            if fall.duration > 0, !still {
                let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
                animation.values = fall.values.map { barHeight($0) }
                animation.keyTimes = fall.keyTimes.map { NSNumber(value: $0) }
                animation.calculationMode = .linear
                animation.duration = fall.duration
                animation.beginTime = now
                bar.add(animation, forKey: "fall")
            }
            let drop = analyser.peakTrajectory(index, from: now)
            let peak = peakLayers[index]
            peak.removeAnimation(forKey: "drop")
            peak.bounds = CGRect(x: 0, y: 0, width: barWidth, height: NotchcastTheme.SpectrumBars.peakHeight)
            let shown = (drop.values.max() ?? 0) >= IslandSpectrumAnalyser.peakVisibleFrom
            peak.isHidden = !shown
            peak.position = CGPoint(x: x(index), y: peakY((still ? drop.values.first : drop.values.last) ?? 0))
            if shown, drop.duration > 0, !still {
                let animation = CAKeyframeAnimation(keyPath: "position.y")
                animation.values = drop.values.map { peakY($0) }
                animation.keyTimes = drop.keyTimes.map { NSNumber(value: $0) }
                animation.calculationMode = .linear
                animation.duration = drop.duration
                animation.beginTime = now
                peak.add(animation, forKey: "drop")
            }
        }
        CATransaction.commit()
    }

    private func peakY(_ level: Double) -> CGFloat { barHeight(level) + NotchcastTheme.SpectrumBars.peakGap }
}

/// The spectrum in SwiftUI: it moves only while `isPlaying`, on screen, without Reduce Motion.
struct IslandSpectrumBars: NSViewRepresentable {
    var isPlaying: Bool
    var visibleOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> IslandSpectrumBarsView {
        let view = IslandSpectrumBarsView(frame: .zero)
        view.visibleOverride = visibleOverride
        return view
    }

    func updateNSView(_ view: IslandSpectrumBarsView, context: Context) {
        view.visibleOverride = visibleOverride
        view.configure(playing: isPlaying, reduceMotion: reduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IslandSpectrumBarsView, context: Context) -> CGSize? {
        CGSize(width: IslandSpectrumBarsView.width, height: NotchcastTheme.SpectrumBars.height)
    }

    static func dismantleNSView(_ view: IslandSpectrumBarsView, coordinator: ()) { view.stop() }
}
