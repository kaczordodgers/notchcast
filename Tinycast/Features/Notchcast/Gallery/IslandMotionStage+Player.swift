#if DEBUG
import AppKit
import QuartzCore

// The stage's scenarios and the clock that plays them. Every duration and curve below is the one the island's code
// runs; only the hold times between changes come from STAGE.md.

extension IslandMotionStage {
    enum Kind { case idle, music, message, longMessage, timer, timerAndMusic, timerEnd }

    struct Scenario {
        let name: String
        /// Closed states and when each one is set.
        var shows: [(time: Double, kind: Kind)]
        var duration: Double
        var musicStart: Double = 0
        var musicPause: Double?
        var timerStart: Double = 0
        var launcher: (opens: Double, closes: Double)?
        /// When the same pill switches to Damian Tools' bars (the visualizers scenario).
        var analyserFrom: Double?

        static let morph = IslandMotion.shrinking.duration
        static let swap = Theme.Duration.hover
        /// The opening: the black grows and stays, the closed content fades, the launcher.s rows fade in on the black.
        static let opened = NotchcastTheme.Opening.dissolveDelay + NotchcastTheme.Opening.dissolve

        static var all: [Scenario] {
            let open = 0.6 + opened + 1.2
            let musicOpen = 1.0 + opened + 1.2
            let growing = 0.6 + Theme.Duration.hover
            let revealing = 1.0 + NotchcastTheme.Opening.dissolveDelay + NotchcastTheme.Opening.dissolve / 2
            let pause = 0.6 + morph + 3
            let musicEnd = pause + swap + 1.2
            let secondMusic = 0.6 + morph + 1.5
            let secondEnd = secondMusic + morph + 2.5
            let timerGone = secondEnd + morph + 1
            return [
                Scenario(name: "open-launcher", shows: [(0, .idle)],
                         duration: open + NotchcastTheme.Opening.returnFade + 0.6, launcher: (0.6, open)),
                Scenario(name: "open-from-music", shows: [(0, .music)],
                         duration: musicOpen + NotchcastTheme.Opening.returnFade + 1, musicStart: -2,
                         launcher: (1, musicOpen)),
                Scenario(name: "cancel-growing", shows: [(0, .idle)], duration: growing + 1, launcher: (0.6, growing)),
                Scenario(name: "cancel-revealing", shows: [(0, .music)], duration: revealing + 1, musicStart: -2,
                         launcher: (1, revealing)),
                Scenario(name: "music", shows: [(0, .idle), (0.6, .music), (musicEnd, .idle)],
                         duration: musicEnd + morph + 0.6, musicStart: 0.6, musicPause: pause),
                Scenario(name: "message", shows: [(0, .idle), (0.6, .message), (0.6 + morph + 2, .idle)],
                         duration: 0.6 + morph + 2 + morph + 0.6),
                Scenario(name: "long-message", shows: [(0, .idle), (0.6, .longMessage), (0.6 + morph + 3, .idle)],
                         duration: 0.6 + morph + 3 + morph + 0.6),
                Scenario(name: "timer-then-music",
                         shows: [(0, .idle), (0.6, .timer), (secondMusic, .timerAndMusic), (secondEnd, .timer),
                                 (timerGone, .idle)],
                         duration: timerGone + morph + 0.6, musicStart: secondMusic, timerStart: 0.6),
                Scenario(name: "timer-end", shows: [(0, .timer), (1, .timerEnd), (1 + morph + 2, .idle)],
                         duration: 1 + morph + 2 + morph + 0.6, timerStart: -0.2),
                Scenario(name: "visualizers", shows: [(0, .music)], duration: 8, musicStart: 0, analyserFrom: 4),
            ]
        }
    }
}

// MARK: Curves

extension IslandMotionStage {
    /// A CA timing function, solved for its progress at `time` in 0...1.
    struct Curve {
        let points: (CGFloat, CGFloat, CGFloat, CGFloat)

        init(_ name: CAMediaTimingFunctionName) {
            let function = CAMediaTimingFunction(name: name)
            var one = [Float](repeating: 0, count: 2), two = [Float](repeating: 0, count: 2)
            function.getControlPoint(at: 1, values: &one)
            function.getControlPoint(at: 2, values: &two)
            points = (CGFloat(one[0]), CGFloat(one[1]), CGFloat(two[0]), CGFloat(two[1]))
        }

        func callAsFunction(_ time: Double) -> CGFloat {
            let x = CGFloat(min(1, max(0, time)))
            func bezier(_ a: CGFloat, _ b: CGFloat, _ s: CGFloat) -> CGFloat {
                3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s
            }
            var low: CGFloat = 0, high: CGFloat = 1
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if bezier(points.0, points.2, mid) < x { low = mid } else { high = mid }
            }
            return bezier(points.1, points.3, (low + high) / 2)
        }
    }

    static let easeInEaseOut = Curve(.easeInEaseOut)
    /// SwiftUI's `.easeOut` and `.easeInOut` are these same cubic curves.
    static let easeOut = Curve(.easeOut)

    /// The island's own springs, as the CA animations run them.
    static let growing = spring(IslandMotion.growing)
    static let shrinking = spring(IslandMotion.shrinking)

    private static func spring(_ spring: IslandMotion.Spring) -> (Double) -> CGFloat {
        let curve = spring.curve()
        return { CGFloat(curve($0)) }
    }

    /// Core Animation interpolates a path point by point; every island outline has the same elements.
    static func mix(_ from: CGPath, _ to: CGPath, _ progress: CGFloat) -> CGPath {
        let a = elements(from), b = elements(to)
        guard a.count == b.count, zip(a, b).allSatisfy({ $0.0 == $1.0 && $0.1.count == $1.1.count }) else {
            return progress < 1 ? from : to
        }
        let path = CGMutablePath()
        for (left, right) in zip(a, b) {
            let points = zip(left.1, right.1).map { p, q in
                CGPoint(x: p.x + (q.x - p.x) * progress, y: p.y + (q.y - p.y) * progress)
            }
            switch left.0 {
            case .moveToPoint: path.move(to: points[0])
            case .addLineToPoint: path.addLine(to: points[0])
            case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closeSubpath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }

    private static func elements(_ path: CGPath) -> [(CGPathElementType, [CGPoint])] {
        var result: [(CGPathElementType, [CGPoint])] = []
        path.applyWithBlock { element in
            let type = element.pointee.type
            let count = switch type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            result.append((type, Array(UnsafeBufferPointer(start: element.pointee.points, count: count))))
        }
        return result
    }
}

// MARK: Bars

extension IslandMotionStage {
    private typealias Orion = NotchcastTheme.Visualizer.Orion
    private typealias Analyser = NotchcastTheme.Visualizer.Analyser

    /// `IslandOrionBars`: from the lowest level, `.easeInOut(cycle).repeatForever(autoreverses:)` delayed by each
    /// bar's offset (a negative delay starts that far into the cycle).
    static func orion(_ index: Int, elapsed: Double) -> CGFloat {
        let phase = (elapsed - Orion.offsets[index]) / Orion.cycle
        guard phase > 0 else { return Orion.lowestLevel }
        let turn = floor(phase)
        let within = phase - turn
        let progress = Int(turn) % 2 == 0 ? within : 1 - within
        return Orion.lowestLevel + (1 - Orion.lowestLevel) * easeInEaseOut(progress)
    }

    /// Damian Tools' synthetic levels and analyser on the scenario's clock, with a fixed seed.
    @MainActor
    final class AnalyserClock {
        private(set) var now: Double
        private var queue: [(time: Double, work: @MainActor () -> Void)] = []
        private(set) var analyser = IslandBarsAnalyser(bars: Analyser.count)
        private(set) var lastReading: Double
        private var source: IslandSyntheticLevels?

        init(start: Double) {
            now = start
            lastReading = start
            let source = IslandSyntheticLevels(
                seed: 20_261_105,
                clock: { [unowned self] in MainActor.assumeIsolated { now } },
                schedule: { [unowned self] delay, work in
                    MainActor.assumeIsolated { queue.append((now + delay, work)) }
                })
            self.source = source
            source.start(bars: Analyser.count) { [unowned self] reading in
                analyser.receive(reading, at: now)
                lastReading = now
            }
        }

        func advance(to time: Double) {
            while let next = queue.enumerated().min(by: { $0.element.time < $1.element.time }),
                  next.element.time <= time {
                queue.remove(at: next.offset)
                now = next.element.time
                next.element.work()
            }
            now = time
        }
    }

    static func drawOrion(_ context: CGContext, in rect: CGRect, scale: (Int) -> CGFloat) {
        context.setFillColor(NotchcastTheme.Colors.barInk.cgColor)
        for index in 0..<Orion.count {
            let x = rect.minX + CGFloat(index) * (Orion.width + Orion.gap)
            context.saveGState()
            context.translateBy(x: x + Orion.width / 2, y: rect.midY)
            context.scaleBy(x: 1, y: scale(index))
            context.addPath(CGPath(roundedRect: CGRect(x: -Orion.width / 2, y: -rect.height / 2, width: Orion.width,
                                                       height: rect.height),
                                   cornerWidth: Orion.width / 2, cornerHeight: Orion.width / 2, transform: nil))
            context.fillPath()
            context.restoreGState()
        }
    }

    /// `IslandAnalyserBarsView`'s geometry: bars stand on the view's bottom, peaks a gap above them.
    static func drawAnalyser(_ context: CGContext, trailing rect: CGRect, clock: AnalyserClock) {
        let width = CGFloat(Analyser.count - 1) * Analyser.width * Analyser.pitch + Analyser.width
        let origin = CGPoint(x: rect.maxX - width, y: rect.minY)
        let maximum = max(Analyser.width, rect.height - Analyser.peak - Analyser.peakGap)
        func height(_ level: Double) -> CGFloat { max(Analyser.width, maximum * CGFloat(level)) }
        context.setFillColor(NotchcastTheme.Colors.barInk.cgColor)
        for index in 0..<Analyser.count {
            let x = origin.x + CGFloat(index) * Analyser.width * Analyser.pitch
            let bar = CGRect(x: x, y: origin.y, width: Analyser.width,
                             height: height(clock.analyser.height(index, at: clock.now)))
            context.addPath(CGPath(roundedRect: bar, cornerWidth: Analyser.width / 2, cornerHeight: Analyser.width / 2,
                                   transform: nil))
            context.fillPath()
            guard clock.analyser.peak(index, at: clock.lastReading) >= IslandBarsAnalyser.peakVisibleFrom else { continue }
            let peak = height(clock.analyser.peak(index, at: clock.now)) + Analyser.peakGap
            context.fill(CGRect(x: x, y: origin.y + peak, width: Analyser.width, height: Analyser.peak))
        }
    }
}
#endif
