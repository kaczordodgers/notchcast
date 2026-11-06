#if DEBUG
import AppKit
import QuartzCore

extension IslandMotionStage {
    /// Plays one scenario: which looks are up, how far each change has gone, and the stage around them.
    @MainActor
    final class Player {
        private let scenario: Scenario
        private let shape: Shape
        private let launcher: CGImage
        private let panel: CGRect
        private var looks: [Content: Look] = [:]
        private var analyser: AnalyserClock?

        init(scenario: Scenario, shape: Shape, looks cache: LookCache, launcher: CGImage) async throws {
            self.scenario = scenario
            self.shape = shape
            self.launcher = launcher
            var needed: Set<Content> = []
            let seconds = Int(scenario.duration.rounded(.up)) + 1
            for (_, kind) in scenario.shows {
                switch kind {
                case .timer: (0...seconds).forEach { needed.insert(.timer(second: $0)) }
                case .timerAndMusic: (0...seconds).forEach { needed.insert(.timerAndMusic(second: $0)) }
                default: needed.insert(Self.content(kind, second: 0))
                }
            }
            var built: [Content: Look] = [:]
            for content in needed { built[content] = try await cache.look(content) }
            looks = built
            panel = CGRect(origin: .zero, size: cache.panelFrame.size)
        }

        private static func content(_ kind: Kind, second: Int) -> Content {
            switch kind {
            case .idle: .idle
            case .music: .music
            case .message: .message
            case .longMessage: .longMessage
            case .timerEnd: .timerEnd
            case .timer: .timer(second: second)
            case .timerAndMusic: .timerAndMusic(second: second)
            }
        }

        private func look(_ kind: Kind, at time: Double) -> Look {
            let second = max(0, Int(floor(time - scenario.timerStart)))
            return looks[Self.content(kind, second: second)] ?? looks.values.first!
        }

        func frame(at time: Double) throws -> CGImage {
            let context = IslandMotionStage.context(IslandMotionStage.stage, opaque: true)
            let stage = CGRect(origin: .zero, size: IslandMotionStage.stage)
            context.setFillColor(CGColor(srgbRed: 0xDF / 255, green: 0xE5 / 255, blue: 0xEE / 255, alpha: 1))
            context.fill(stage)
            let current = scenario.shows.lastIndex { $0.time <= time } ?? 0
            let shown = look(scenario.shows[current].kind, at: time)
            let offset = stage.height - panel.height
            drawMenuBar(context)
            context.saveGState()
            context.translateBy(x: 0, y: offset)
            drawIsland(context, current: current, shown: shown, at: time)
            context.restoreGState()
            // The launcher's rows, shot from the live app, fade in on the black once it has arrived and vanish at once.
            if let launcher = scenario.launcher, time >= launcher.opens, time < launcher.closes {
                let at = look(scenario.shows[current].kind, at: launcher.opens)
                let shown = time - launcher.opens - NotchcastTheme.Opening.dissolveDelay
                context.saveGState()
                context.setAlpha(min(1, max(0, CGFloat(shown / NotchcastTheme.Opening.dissolve))))
                context.draw(self.launcher, in: launcherFrame(under: at).offsetBy(dx: 0, dy: offset))
                context.restoreGState()
            }
            if let notch = shape.notch {
                let rect = CGRect(x: stage.midX - notch.width / 2, y: stage.height - notch.height,
                                  width: notch.width, height: notch.height)
                context.addPath(IslandSilhouette.path(
                    in: rect, shoulder: 0, bottomRadius: NotchcastTheme.Corners.bottomRadius(height: notch.height)))
                context.setFillColor(.black)
                context.fillPath()
            }
            guard let image = context.makeImage() else { throw StageFailure.message("no frame") }
            return image
        }

        /// Where the expanded launcher sits: centred on the island, its top under the notch or level with the pill.
        private func launcherFrame(under look: Look) -> CGRect {
            let size = NotchcastTheme.Launcher.size
            let top = look.body.maxY - (shape.notch?.height ?? 0)
            return CGRect(x: look.body.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        }

        // MARK: Island

        private func drawIsland(_ context: CGContext, current: Int, shown: Look, at time: Double) {
            let change = scenario.shows[current].time
            let previous = current > 0 ? look(scenario.shows[current - 1].kind, at: time) : nil
            let since = time - change
            var path = previous.map { mix($0.path, shown.path, morph(from: $0.path, to: shown.path)(since)) }
                ?? shown.path
            let swap = previous == nil ? 1 : easeOut(since / Scenario.swap)
            var surface: CGFloat = 1
            var content: CGFloat = 1
            if let launcher = scenario.launcher, time >= launcher.opens {
                let launcherPath = IslandSilhouette.path(IslandPanel.launcherOutline(
                    launcherFrame(under: shown), notch: shape.notch != nil, screenTop: shown.body.maxY))
                if time < launcher.closes {
                    (path, content, surface) = opening(shown.path, launcherPath, at: time - launcher.opens)
                } else {
                    // The launcher gone: the black shrinks back from wherever it was, the closed row fading in.
                    let since = time - launcher.closes
                    let from = opening(shown.path, launcherPath, at: launcher.closes - launcher.opens)
                    path = mix(from.path, shown.path, shrinking(since))
                    content = from.content + (1 - from.content) * min(1, CGFloat(since / IslandMotion.crossFade))
                }
            }
            context.clip(to: panel)
            context.setAlpha(surface)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.addPath(path)
            context.setFillColor(.black)
            context.fillPath()
            context.addPath(path)
            context.clip()
            if let previous, swap < 1 { drawContent(context, previous, alpha: (1 - swap) * content, at: time) }
            drawContent(context, shown, alpha: swap * content, at: time)
            context.endTransparencyLayer()
        }

        /// The opening `opened` seconds in: the black springing to the launcher and staying as its surface, the closed
        /// content fading out.
        private func opening(_ closed: CGPath, _ launcher: CGPath, at opened: Double)
            -> (path: CGPath, content: CGFloat, surface: CGFloat)
        {
            (mix(closed, launcher, IslandMotionStage.growing(opened)), max(0, 1 - CGFloat(opened / IslandMotion.crossFade)), 1)
        }

        /// `IslandMotion.choice` for two closed looks: a larger outline grows, a smaller one shrinks.
        private func morph(from: CGPath, to: CGPath) -> (Double) -> CGFloat {
            func area(_ path: CGPath) -> CGFloat { path.boundingBoxOfPath.width * path.boundingBoxOfPath.height }
            return area(to) > area(from) ? growing : shrinking
        }

        private func drawContent(_ context: CGContext, _ look: Look, alpha: CGFloat, at time: Double) {
            guard alpha > 0 else { return }
            context.saveGState()
            context.setAlpha(alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.draw(look.content, in: panel)
            if let bars = look.bars {
                context.setFillColor(.black)
                context.fill(bars.insetBy(dx: -1, dy: -1))
                if let from = scenario.analyserFrom, time >= from {
                    let clock = analyser ?? AnalyserClock(start: from)
                    analyser = clock
                    clock.advance(to: time)
                    drawAnalyser(context, trailing: bars, clock: clock)
                } else {
                    drawOrion(context, in: bars) { self.barScale($0, at: time) }
                }
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }

        /// Playing sways; a pause is a state change, so the bars ease to rest on the content swap's curve.
        private func barScale(_ index: Int, at time: Double) -> CGFloat {
            let resting = CGFloat(NotchcastTheme.Visualizer.Orion.restingLevel)
            guard let pause = scenario.musicPause, time >= pause else {
                return orion(index, elapsed: time - scenario.musicStart)
            }
            let from = orion(index, elapsed: pause - scenario.musicStart)
            return from + (resting - from) * easeOut((time - pause) / Scenario.swap)
        }

        // MARK: Menu bar

        private func drawMenuBar(_ context: CGContext) {
            let stage = IslandMotionStage.stage
            let bar = CGRect(x: 0, y: stage.height - shape.menuBar, width: stage.width, height: shape.menuBar)
            context.setFillColor(CGColor(srgbRed: 0xF4 / 255, green: 0xF6 / 255, blue: 0xF9 / 255, alpha: 1))
            context.fill(bar)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(srgbRed: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 1),
            ]
            let left = NSAttributedString(string: "Finder  File  Edit  View  Go", attributes: attributes)
            let right = NSAttributedString(string: "Wi-Fi  Bluetooth  Battery  Sound  Thu 13:54", attributes: attributes)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let y = bar.minY + (bar.height - left.size().height) / 2
            left.draw(at: CGPoint(x: 12, y: y))
            right.draw(at: CGPoint(x: 788 - right.size().width, y: y))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
#endif
