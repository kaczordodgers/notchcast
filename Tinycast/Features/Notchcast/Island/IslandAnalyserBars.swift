import AppKit
import QuartzCore
import SwiftUI

/// Damian Tools' bars on their own layers. Each reading installs one linear fall per bar and a sampled drop per
/// peak; between readings this process does nothing. Paused, hidden or under Reduce Motion: a dot for each bar.
final class IslandAnalyserBarsView: NSView {
    private typealias Bars = NotchcastTheme.Visualizer.Analyser
    private var barLayers: [CALayer] = []
    private var peakLayers: [CALayer] = []
    private var analyser = IslandBarsAnalyser(bars: Bars.count)
    private let source: IslandLevelSource
    private var playing = false
    private var still = false
    private var occlusion: NotificationToken?

    init(source: IslandLevelSource) {
        self.source = source
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(false)
        barLayers = (0..<Bars.count).map { _ in Self.inkLayer() }
        peakLayers = (0..<Bars.count).map { _ in Self.inkLayer() }
        (barLayers + peakLayers).forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(playing: Bool, still: Bool) {
        self.playing = playing
        self.still = still
        update()
    }

    func stop() {
        playing = false
        update()
    }

    private static func inkLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NotchcastTheme.Colors.barInk.cgColor
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        occlusion = window.map { window in
            NotificationToken(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }, center: .default)
        }
        update()
    }

    override func layout() { super.layout(); update() }

    private var onScreen: Bool {
        !isHiddenOrHasHiddenAncestor && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }

    private var maximumBar: CGFloat { max(Bars.width, bounds.height - Bars.peak - Bars.peakGap) }

    private func update() {
        if playing && !still && onScreen {
            guard !source.isRunning else { return }
            source.start(bars: barLayers.count) { [weak self] in self?.receive($0) }
        } else {
            if source.isRunning { source.stop() }
            analyser.reset()
            rest()
        }
    }

    private func rest() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            bar.removeAllAnimations()
            bar.bounds = CGRect(x: 0, y: 0, width: Bars.width, height: Bars.width)
            bar.position = CGPoint(x: x(index), y: 0)
            bar.cornerRadius = Bars.width / 2
            peakLayers[index].removeAllAnimations()
            peakLayers[index].isHidden = true
        }
        CATransaction.commit()
    }

    private func x(_ index: Int) -> CGFloat { CGFloat(index) * Bars.width * Bars.pitch + Bars.width / 2 }

    private func barHeight(_ level: Double) -> CGFloat { max(Bars.width, maximumBar * CGFloat(level)) }

    private func peakY(_ level: Double) -> CGFloat { barHeight(level) + Bars.peakGap }

    private func receive(_ reading: IslandLevelReading) {
        let now = ProcessInfo.processInfo.systemUptime
        analyser.receive(reading, at: now)
        let mediaNow = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let fall = analyser.barTrajectory(index, from: now)
            bar.removeAnimation(forKey: "fall")
            bar.bounds = CGRect(x: 0, y: 0, width: Bars.width, height: barHeight(fall.values.last ?? 0))
            bar.position = CGPoint(x: x(index), y: 0)
            bar.cornerRadius = Bars.width / 2
            if fall.duration > 0 {
                bar.add(keyframes("bounds.size.height", fall.values.map(barHeight), fall, at: mediaNow), forKey: "fall")
            }
            let drop = analyser.peakTrajectory(index, from: now)
            let peak = peakLayers[index]
            peak.removeAnimation(forKey: "drop")
            peak.bounds = CGRect(x: 0, y: 0, width: Bars.width, height: Bars.peak)
            let shown = (drop.values.max() ?? 0) >= IslandBarsAnalyser.peakVisibleFrom
            peak.isHidden = !shown
            peak.position = CGPoint(x: x(index), y: peakY(drop.values.last ?? 0))
            if shown, drop.duration > 0 {
                peak.add(keyframes("position.y", drop.values.map(peakY), drop, at: mediaNow), forKey: "drop")
            }
        }
        CATransaction.commit()
    }

    private func keyframes(
        _ path: String, _ values: [CGFloat],
        _ trajectory: (values: [Double], keyTimes: [Double], duration: TimeInterval), at start: CFTimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = trajectory.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = trajectory.duration
        animation.beginTime = start
        return animation
    }
}

/// Damian Tools' bars in SwiftUI: they move only while playing, on screen, with Reduce Motion and Show animations
/// off neither.
struct IslandAnalyserBars: NSViewRepresentable {
    var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Bars = NotchcastTheme.Visualizer.Analyser

    func makeNSView(context: Context) -> IslandAnalyserBarsView {
        IslandAnalyserBarsView(source: IslandSyntheticLevels())
    }

    func updateNSView(_ view: IslandAnalyserBarsView, context: Context) {
        view.configure(playing: isPlaying, still: reduceMotion || !Motion.isEnabled)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IslandAnalyserBarsView, context: Context) -> CGSize? {
        CGSize(width: CGFloat(Bars.count - 1) * Bars.width * Bars.pitch + Bars.width,
               height: NotchcastTheme.Visualizer.height)
    }

    static func dismantleNSView(_ view: IslandAnalyserBarsView, coordinator: ()) { view.stop() }
}

/// The closed island's visualizer: Orion's until Damian picks one in the debug lab.
struct IslandVisualizer: View {
    enum Style: CaseIterable {
        case orion
        case analyser
    }

    let isPlaying: Bool
    var style = NotchcastTheme.Visualizer.closedStyle

    var body: some View {
        switch style {
        case .orion: IslandOrionBars(moving: isPlaying)
        case .analyser: IslandAnalyserBars(isPlaying: isPlaying)
        }
    }
}
