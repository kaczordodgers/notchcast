#if DEBUG
import AppKit
import SwiftUI

/// Frames of the island's motion on a fixed stage (`NOTCHCAST_STAGE=<folder>`): the real panel gives every outline
/// and the closed content; the curves the surface plays are evaluated at each frame's time, so a frame is the moment
/// the screen would show. Launcher: a picture of the real launcher at its real frame; the glass cannot render here.
@MainActor
enum GalleryStage {
    static let fps: Double = 25
    static let canvas = CGSize(width: 800, height: 520)
    static let launcherHeight = NotchcastTheme.Launcher.size.height

    struct Shape {
        let name: String
        let display: CGRect
        let notch: CGRect?
        let menuBar: CGFloat
    }

    static let shapes = [
        Shape(name: "mba", display: CGRect(x: 0, y: 0, width: 1470, height: 956),
              notch: CGRect(x: 735 - 92, y: 956 - 32, width: 184, height: 32), menuBar: 37),
        Shape(name: "ext", display: CGRect(x: 0, y: 0, width: 1920, height: 1080), notch: nil, menuBar: 24),
    ]

    /// What the island shows from one moment until the next step, held `hold` seconds once its transition settled.
    struct Step {
        var state: String
        var hold: TimeInterval
        var message: String? = nil
        var launcher = false
    }

    static let scenarios: [(name: String, steps: [Step])] = [
        ("open-launcher", [Step(state: "idle", hold: 0.6), Step(state: "idle", hold: 1.2, launcher: true),
                           Step(state: "idle", hold: 0.6)]),
        ("open-from-music", [Step(state: "music", hold: 1.0), Step(state: "music", hold: 1.2, launcher: true),
                             Step(state: "music", hold: 1.0)]),
        ("music", [Step(state: "idle", hold: 0.6), Step(state: "music", hold: 3.0),
                   Step(state: "music-paused", hold: 1.2), Step(state: "idle", hold: 0.6)]),
        ("message", [Step(state: "idle", hold: 0.6), Step(state: "idle", hold: 2.0, message: "airpods"),
                     Step(state: "idle", hold: 0.6)]),
        ("long-message", [Step(state: "idle", hold: 0.6), Step(state: "idle", hold: 3.0, message: "long-message"),
                          Step(state: "idle", hold: 0.6)]),
        ("timer-then-music", [Step(state: "idle", hold: 0.6), Step(state: "timer", hold: 1.5),
                              Step(state: "two-at-once", hold: 2.5), Step(state: "timer", hold: 1.0),
                              Step(state: "idle", hold: 0.6)]),
        ("timer-end", [Step(state: "timer", hold: 1.0), Step(state: "timer-end", hold: 2.0),
                       Step(state: "idle", hold: 0.6)]),
    ]

    static let messages: [String: IslandMessage] = [
        "airpods": IslandMessage(id: UUID(), tone: .neutral, text: "AirPods: Connected", isProgress: false, onCancel: nil),
        "long-message": IslandMessage(id: UUID(), tone: .neutral, text: "Couldn't paste some dictation into the app",
                                      isProgress: false, onCancel: nil, detail: "The text is on the clipboard instead"),
    ]

    static func runIfRequested(_ core: AppCore) -> Bool {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHCAST_STAGE"] else { return false }
        Task { @MainActor in
            do {
                let output = URL(filePath: directory, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let launcher = ProcessInfo.processInfo.environment["NOTCHCAST_STAGE_LAUNCHER"]
                    .flatMap { NSImage(contentsOfFile: $0) }
                print("stage: launcher picture \(launcher == nil ? "missing" : "loaded")")
                logCurves()
                for scenario in scenarios {
                    for shape in shapes {
                        let count = try await render(scenario.steps, shape: shape, launcher: launcher,
                                                     into: output.appending(path: "\(scenario.name)-\(shape.name)"))
                        print("stage: \(scenario.name)-\(shape.name) \(count) frames")
                    }
                }
                let count = try await renderVisualizers(shape: shapes[1], into: output.appending(path: "visualizers-ext"))
                print("stage: visualizers-ext \(count) frames")
                print("stage: PASS")
                exit(0)
            } catch {
                print("stage: FAIL \(error)")
                exit(1)
            }
        }
        return true
    }

    // MARK: Curves

    /// The spring the surface plays for a motion (`IslandSurfaceView.springAnimation`).
    static func spring(_ motion: IslandMotion) -> Spring? {
        switch motion {
        case .open, .change: NotchcastTheme.Motion.grow
        case .close: NotchcastTheme.Motion.shrink
        case .fade, .instant: nil
        }
    }

    /// Core Animation's own settling time for those parameters: the animation's duration on screen.
    static func settling(_ spring: Spring) -> TimeInterval {
        let animation = CASpringAnimation()
        animation.mass = CGFloat(spring.mass)
        animation.stiffness = CGFloat(spring.stiffness)
        animation.damping = CGFloat(spring.damping)
        return animation.settlingDuration
    }

    /// Core Animation's named curves as cubic Béziers, solved at a fraction of their duration.
    nonisolated static func easeOut(_ fraction: Double) -> CGFloat { CGFloat(cubic(fraction, 0, 0, 0.58, 1)) }
    nonisolated static func easeInOut(_ fraction: Double) -> CGFloat { CGFloat(cubic(fraction, 0.42, 0, 0.58, 1)) }

    nonisolated static func cubic(_ fraction: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t
        }
        let x = min(1, max(0, fraction))
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if bezier(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, y1, y2)
    }

    /// A fade of `duration` that starts `delay` in, from 0 to 1, on the surface's curve.
    nonisolated static func fade(_ time: TimeInterval, _ duration: TimeInterval, delay: TimeInterval = 0,
                                 curve: (Double) -> CGFloat = easeOut) -> CGFloat {
        curve((time - delay) / duration)
    }

    static func logCurves() {
        for motion in [IslandMotion.open, .close, .change] {
            guard let spring = spring(motion) else { continue }
            print("stage: \(motion) spring mass \(spring.mass) stiffness \(spring.stiffness) damping \(spring.damping)"
                  + " settling \(settling(spring))")
        }
        let kit = NotchcastTheme.Motion.self
        print("stage: content in \(kit.contentIn) out \(kit.contentOut) hold \(kit.contentHold) landing \(kit.landing),"
              + " black out \(kit.blackOut) in \(kit.blackIn)")
    }

    /// A transition between two settled outlines as the surface plays it: Core Animation moves every point of the
    /// path on the spring, element by element, so the frame does the same.
    @MainActor
    struct Transition {
        let from: CGPath
        let to: CGPath
        let spring: Spring?

        var duration: TimeInterval { spring.map(settling) ?? 0 }

        func progress(at time: TimeInterval) -> CGFloat {
            guard let spring, time < duration else { return 1 }
            return CGFloat(spring.value(target: 1.0, time: max(0, time)))
        }

        func path(at time: TimeInterval) -> CGPath { blend(from, to, progress(at: time)) }
    }

    nonisolated static func blend(_ from: CGPath, _ to: CGPath, _ progress: CGFloat) -> CGPath {
        var points: [[CGPoint]] = []
        from.applyWithBlock { element in
            let count = element.pointee.type == .addCurveToPoint ? 3 : element.pointee.type == .addQuadCurveToPoint ? 2
                : element.pointee.type == .closeSubpath ? 0 : 1
            points.append((0..<count).map { element.pointee.points[$0] })
        }
        let path = CGMutablePath()
        var index = 0
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
        }
        to.applyWithBlock { element in
            let start = index < points.count ? points[index] : []
            index += 1
            let target = element.pointee.points
            func point(_ at: Int) -> CGPoint { at < start.count ? mix(start[at], target[at]) : target[at] }
            switch element.pointee.type {
            case .moveToPoint: path.move(to: point(0))
            case .addLineToPoint: path.addLine(to: point(0))
            case .addQuadCurveToPoint: path.addQuadCurve(to: point(1), control: point(0))
            case .addCurveToPoint: path.addCurve(to: point(2), control1: point(0), control2: point(1))
            case .closeSubpath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }

    // MARK: One scenario

    static func render(_ steps: [Step], shape: Shape, launcher: NSImage?, into folder: URL) async throws -> Int {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let panel = IslandPanel(screenFrame: shape.display, hardwareNotch: shape.notch)
        defer { panel.close() }
        guard let surface = panel.contentView as? IslandSurfaceView else { throw GalleryFailure.capture("no surface") }
        let (host, outgoing) = surface.stageViews
        var frame = 0
        var time: TimeInterval = 0
        var previous: (outline: IslandSurfaceView.Outline, stage: IslandStage)?
        var musicStart: TimeInterval?
        var timerStart: TimeInterval?
        var base = AnyView(EmptyView())

        func apply(_ step: Step, at moment: TimeInterval, deciding: Bool = false) {
            let timerElapsed = timerStart.map { moment - $0 } ?? 0
            // On only as a step begins, for the panel to decide its crossfade.
            Motion.isEnabled = deciding
            panel.setContent(open: AnyView(EmptyView()), closed: closedState(step.state, timerElapsed: timerElapsed),
                             header: AnyView(EmptyView()))
            panel.setMessage(step.message.flatMap { messages[$0] })
            Motion.isEnabled = false
            panel.setLauncher(height: step.launcher ? launcherHeight : nil, animated: false)
            surface.layer?.backgroundColor = nil
            base = host.rootView
            host.rootView = AnyView(base.environment(\.islandStillTime, musicStart.map { moment - $0 } ?? 0))
        }

        func settle(until expected: IslandSurfaceView.Outline?) async throws -> IslandSurfaceView.Outline {
            var last = panel.outline
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(40))
                surface.layoutSubtreeIfNeeded()
                let now = panel.outline
                if let expected { if now == expected { return now } } else if now == last { return now }
                last = now
            }
            return last
        }

        var lastRow: (state: IslandClosedState, message: UUID?)?
        for (index, step) in steps.enumerated() {
            let shows = (state: closedState(step.state, timerElapsed: 0), message: step.message.flatMap { messages[$0] }?.id)
            let handover = lastRow.flatMap {
                IslandMotion.handover(from: $0.state, message: $0.message, to: shows.state, message: shows.message)
            }
            lastRow = shows
            let hasMusic = ["music", "music-paused", "two-at-once"].contains(step.state)
            let hasTimer = ["timer", "two-at-once"].contains(step.state)
            if hasMusic { musicStart = musicStart ?? time } else { musicStart = nil }
            if hasTimer { timerStart = timerStart ?? time } else { timerStart = nil }
            let start = time
            let picture = outgoing.layer?.contents as AnyObject?
            apply(step, at: start, deciding: true)
            let settled = try await settle(until: nil)
            let stage: IslandStage = step.launcher ? .launcher : .closed
            let crossfades = outgoing.layer?.contents as AnyObject? !== picture
            let motion = previous.map {
                IslandMotion.choice(from: $0.stage, to: stage, reduceMotion: false, animationsEnabled: true)
            }
            let transition = previous.map { Transition(from: $0.outline.path, to: settled.path, spring: motion.flatMap(spring)) }
            // `IslandSurfaceView.carry`: the row starts where the old one stood and slides with the shape.
            let carry = motion == .change ? (previous?.outline.contentMidX ?? 0) - settled.contentMidX : 0
            let launcherOpens = step.launcher && index > 0 && !steps[index - 1].launcher
            let launcherCloses = !step.launcher && index > 0 && steps[index - 1].launcher
            let end = start + (transition?.duration ?? 0) + step.hold
            while time < end - 1e-9 {
                let since = time - start
                if hasTimer, since > 0 {
                    apply(step, at: time)
                    _ = try await settle(until: settled)
                } else {
                    host.rootView = AnyView(base.environment(\.islandStillTime, musicStart.map { time - $0 } ?? 0))
                }
                try await Task.sleep(for: .milliseconds(16))
                surface.layoutSubtreeIfNeeded()
                // The surface's own fades, solved for this frame (`IslandSurfaceView.setOpacity`, `setClosedContent`,
                // `setSurfaceOpacity`); the black never fades the content, which sits in its own layers.
                let kit = NotchcastTheme.Motion.self
                var row: CGFloat = 1
                var old: CGFloat = 0
                var black: CGFloat = 1
                if launcherOpens {
                    row = 1 - fade(since, kit.contentOut)
                    black = 1 - fade(since, kit.blackOut)
                } else if launcherCloses {
                    row = fade(since, kit.contentIn, delay: kit.landing)
                    black = fade(since, kit.blackIn, delay: kit.landing)
                } else if step.launcher {
                    row = 0
                    black = 0
                } else if crossfades {
                    row = fade(since, kit.contentIn)
                    let holds = handover == .holds
                    old = 1 - fade(since, kit.contentOut, delay: holds ? kit.contentHold : 0, curve: holds ? easeInOut : easeOut)
                }
                host.isHidden = false
                host.layer?.opacity = Float(row)
                outgoing.isHidden = old <= 0
                outgoing.layer?.opacity = Float(old)
                let slide = carry * (1 - (transition?.progress(at: since) ?? 1))
                for layer in [host.layer, outgoing.layer] {
                    layer?.setAffineTransform(CGAffineTransform(translationX: slide, y: 0))
                }
                let path = transition?.path(at: since) ?? settled.path
                frame += 1
                try write(frame: frame, into: folder) { graphics in
                    drawStage(graphics, shape: shape, launcher: step.launcher ? launcher : nil,
                              launcherFrame: panel.launcherFrame(height: launcherHeight), island: { graphics in
                        graphics.translateBy(x: panel.frame.minX, y: panel.frame.minY)
                        graphics.setFillColor(NSColor.black.withAlphaComponent(black).cgColor)
                        graphics.addPath(path)
                        graphics.fillPath()
                        graphics.addPath(path)
                        graphics.clip()
                        if let band = panel.cameraBand {
                            graphics.setFillColor(NSColor.black.cgColor)
                            graphics.fill(band)
                        }
                        guard row > 0 || old > 0, let layer = surface.layer else { return }
                        layer.displayIfNeeded()
                        // The clip above is this frame's outline; the surface's own mask is already the settled one.
                        let mask = layer.mask
                        layer.mask = nil
                        layer.render(in: graphics)
                        layer.mask = mask
                    })
                }
                time += 1 / fps
            }
            previous = (settled, stage)
        }
        return frame
    }

    /// One timer through a scenario, as a producer keeps its activity's id while the value ticks.
    static let timerID = UUID()

    /// The gallery's sample states; a timer counts from the moment it started on the stage, not from the render.
    static func closedState(_ key: String, timerElapsed: TimeInterval) -> IslandClosedState {
        let timer = IslandActivity(id: timerID, kind: .timer, title: "Tea timer",
                                   value: .timeLeft(Date().addingTimeInterval(299.7 - timerElapsed)))
        switch key {
        case "timer": return IslandClosedState(primary: timer)
        case "two-at-once": return IslandClosedState(primary: timer, music: GalleryPages.sampleMusic)
        default: return GalleryPages.closedState(key)
        }
    }

    // MARK: Visualizers

    /// The music pill with Orion's bars (the real state) for 4 s, then the same pill with Damian Tools' spectrum
    /// (the comparison row's pill, not a product state) for 4 s, both from a fixed seed.
    static func renderVisualizers(shape: Shape, into folder: URL) async throws -> Int {
        var count = try await render([Step(state: "music", hold: 4.0)], shape: shape, launcher: nil, into: folder)
        let song = GalleryPages.sampleMusic
        func pill(at time: TimeInterval) -> AnyView {
            AnyView(HStack(spacing: NotchcastTheme.Pill.artworkGap) {
                IslandArtwork(image: song.artwork)
                IslandTrackText(title: song.title, artist: song.artist)
                IslandSpectrumBars(isPlaying: true, visibleOverride: true, seed: 7)
                    .padding(.leading, NotchcastTheme.Pill.gap - NotchcastTheme.Pill.artworkGap)
            }
            .padding(.horizontal, NotchcastTheme.Pill.inset)
            .frame(height: NotchcastTheme.rowHeight)
            .fixedSize()
            .foregroundStyle(NotchcastTheme.Colors.primary)
            .environment(\.colorScheme, .dark)
            .environment(\.islandStillTime, time))
        }
        let hosting = NSHostingView(rootView: pill(at: 0))
        hosting.sizingOptions = []
        let size = CGSize(width: max(NotchcastTheme.monitorPill.width, hosting.fittingSize.width.rounded(.up)),
                          height: NotchcastTheme.rowHeight)
        let rect = CGRect(x: shape.display.midX - size.width / 2,
                          y: shape.display.maxY - NotchcastTheme.Pill.topGap - size.height, width: size.width, height: size.height)
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        hosting.frame = container.bounds
        container.addSubview(hosting)
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = container
        defer { window.close() }
        let path = IslandSilhouette.path(in: rect, shoulder: 0, bottomRadius: NotchcastTheme.statusRadius,
                                         topRadius: NotchcastTheme.statusRadius)
        for index in 0..<Int(4 * fps) {
            let time = TimeInterval(index) / fps
            hosting.rootView = pill(at: time)
            try await Task.sleep(for: .milliseconds(16))
            container.layoutSubtreeIfNeeded()
            count += 1
            try write(frame: count, into: folder) { graphics in
                drawStage(graphics, shape: shape, launcher: nil, launcherFrame: .zero, island: { graphics in
                    graphics.setFillColor(NSColor.black.cgColor)
                    graphics.addPath(path)
                    graphics.fillPath()
                    graphics.addPath(path)
                    graphics.clip()
                    graphics.translateBy(x: rect.minX, y: rect.minY)
                    guard let layer = container.layer else { return }
                    layer.displayIfNeeded()
                    layer.render(in: graphics)
                })
            }
        }
        return count
    }

    // MARK: The stage

    /// Everything in screen points, bottom-left origin, the canvas's top-left at the screen's top centre.
    static func drawStage(_ graphics: CGContext, shape: Shape, launcher: NSImage?, launcherFrame: CGRect,
                          island: (CGContext) -> Void) {
        let centerX = shape.notch?.midX ?? shape.display.midX
        let origin = CGPoint(x: centerX - canvas.width / 2, y: shape.display.maxY - canvas.height)
        graphics.translateBy(x: -origin.x, y: -origin.y)
        graphics.setFillColor(NSColor(srgbRed: 0xDF / 255, green: 0xE5 / 255, blue: 0xEE / 255, alpha: 1).cgColor)
        graphics.fill(CGRect(origin: origin, size: canvas))
        // The launcher sits under the menu bar (`NSWindow.Level.palette` is below the main menu).
        if let launcher {
            NSGraphicsContext.saveGraphicsState()
            launcher.draw(in: launcherFrame, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        let bar = CGRect(x: origin.x, y: shape.display.maxY - shape.menuBar, width: canvas.width, height: shape.menuBar)
        graphics.setFillColor(NSColor(srgbRed: 0xF4 / 255, green: 0xF6 / 255, blue: 0xF9 / 255, alpha: 1).cgColor)
        graphics.fill(bar)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(srgbRed: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 1)]
        let left = NSAttributedString(string: "Finder  File  Edit  View  Go", attributes: attributes)
        let right = NSAttributedString(string: "Wi-Fi  Bluetooth  Battery  Sound  Thu 13:54", attributes: attributes)
        let textY = bar.minY + (bar.height - left.size().height) / 2
        left.draw(at: CGPoint(x: origin.x + 12, y: textY))
        right.draw(at: CGPoint(x: origin.x + 788 - right.size().width, y: textY))
        graphics.saveGState()
        island(graphics)
        graphics.restoreGState()
        if let notch = shape.notch {
            graphics.setFillColor(NSColor.black.cgColor)
            graphics.fill(notch)
        }
    }

    static func write(frame: Int, into folder: URL, draw: (CGContext) -> Void) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * 2), pixelsHigh: Int(canvas.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw GalleryFailure.capture("frame \(frame)")
        }
        bitmap.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let graphics = context.cgContext
        graphics.scaleBy(x: 2, y: 2)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { draw(graphics) }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryFailure.capture("frame \(frame)")
        }
        try png.write(to: folder.appending(path: String(format: "frame-%04d.png", frame)))
    }
}
#endif
