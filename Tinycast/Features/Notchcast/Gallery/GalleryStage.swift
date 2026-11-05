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

    /// The surface's open spring (`IslandSurfaceView.pathAnimation`): Core Animation's own parameters, solved.
    static let openSpring = CASpringAnimation(perceptualDuration: IslandMotion.open.duration, bounce: 0)
    static var openSettle: TimeInterval { openSpring.settlingDuration }

    /// Where a damped spring from 0 to 1 at rest is after `time` seconds.
    static func springProgress(_ time: TimeInterval) -> CGFloat {
        guard time > 0 else { return 0 }
        guard time < openSettle else { return 1 }
        let mass = Double(openSpring.mass), stiffness = Double(openSpring.stiffness), damping = Double(openSpring.damping)
        let omega = (stiffness / mass).squareRoot()
        let zeta = damping / (2 * (stiffness * mass).squareRoot())
        if abs(zeta - 1) < 1e-6 {
            return CGFloat(1 - (1 + omega * time) * exp(-omega * time))
        }
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * time)
            return CGFloat(1 - decay * (cos(damped * time) + zeta * omega / damped * sin(damped * time)))
        }
        let root = omega * (zeta * zeta - 1).squareRoot()
        let r1 = -zeta * omega + root, r2 = -zeta * omega - root
        return CGFloat(1 - (r2 * exp(r1 * time) - r1 * exp(r2 * time)) / (r2 - r1))
    }

    static func logCurves() {
        let swiftUI = Spring(duration: IslandMotion.open.duration, bounce: 0)
        print("stage: open spring CA mass \(openSpring.mass) stiffness \(openSpring.stiffness) damping \(openSpring.damping)"
              + " settling \(openSpring.settlingDuration)")
        print("stage: open spring SwiftUI mass \(swiftUI.mass) stiffness \(swiftUI.stiffness) damping \(swiftUI.damping)"
              + " settling \(swiftUI.settlingDuration)")
        print("stage: close easeInEaseOut \(IslandMotion.close.duration), content fade \(IslandMotion.fade.duration),"
              + " black fade \(NotchcastTheme.Motion.launcherEnter) / \(NotchcastTheme.Motion.launcherExit)")
    }

    /// A transition between two settled outlines, as the surface plays it (`IslandPanel.present`): the spring into
    /// the launcher, the ease-in-out out of it and for every closed change; a path whose element count changes
    /// cannot be interpolated by Core Animation, so it cuts.
    @MainActor
    struct Transition {
        let from: IslandSurfaceView.Outline
        let to: IslandSurfaceView.Outline
        let opens: Bool
        let cuts: Bool

        var duration: TimeInterval { opens ? openSettle : IslandMotion.close.duration }

        func outline(at time: TimeInterval) -> IslandSurfaceView.Outline {
            if cuts || time >= duration { return to }
            let progress = opens ? springProgress(time) : CGFloat(IslandCurve.easeInOut(time / duration))
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
            let rect = CGRect(x: mix(from.rect.minX, to.rect.minX), y: mix(from.rect.minY, to.rect.minY),
                              width: mix(from.rect.width, to.rect.width), height: mix(from.rect.height, to.rect.height))
            return .init(rect: rect, shoulder: mix(from.shoulder, to.shoulder), radius: mix(from.radius, to.radius),
                         topRadius: mix(from.topRadius, to.topRadius), bubble: mix(from.bubble, to.bubble),
                         bubbleGap: to.bubbleGap)
        }
    }

    // MARK: One scenario

    static func render(_ steps: [Step], shape: Shape, launcher: NSImage?, into folder: URL) async throws -> Int {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let panel = IslandPanel(screenFrame: shape.display, hardwareNotch: shape.notch)
        defer { panel.close() }
        guard let surface = panel.contentView,
              let host = surface.subviews.compactMap({ $0 as? NSHostingView<AnyView> }).last else {
            throw GalleryFailure.capture("no closed host")
        }
        var frame = 0
        var time: TimeInterval = 0
        var previous: IslandSurfaceView.Outline?
        var musicStart: TimeInterval?
        var timerStart: TimeInterval?
        var base = AnyView(EmptyView())

        func apply(_ step: Step, at moment: TimeInterval) {
            let timerElapsed = timerStart.map { moment - $0 } ?? 0
            panel.setContent(open: AnyView(EmptyView()), closed: closedState(step.state, timerElapsed: timerElapsed),
                             header: AnyView(EmptyView()))
            panel.setMessage(step.message.flatMap { messages[$0] })
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

        for (index, step) in steps.enumerated() {
            let hasMusic = ["music", "music-paused", "two-at-once"].contains(step.state)
            let hasTimer = ["timer", "two-at-once"].contains(step.state)
            if hasMusic { musicStart = musicStart ?? time } else { musicStart = nil }
            if hasTimer { timerStart = timerStart ?? time } else { timerStart = nil }
            let start = time
            apply(step, at: start)
            let settled = try await settle(until: nil)
            let transition = previous.map { from in
                Transition(from: from, to: settled, opens: step.launcher && !steps[index - 1].launcher,
                           cuts: (from.bubble > 0) != (settled.bubble > 0))
            }
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
                host.isHidden = false
                host.layer?.opacity = 1
                let outline = transition?.outline(at: since) ?? settled
                // Content and black fade only when the launcher takes the black or gives it back.
                var content: CGFloat = 1
                var black: CGFloat = 1
                if launcherOpens {
                    content = 1 - fade(since, IslandMotion.fade.duration)
                    black = 1 - fade(since, NotchcastTheme.Motion.launcherEnter)
                } else if launcherCloses {
                    content = fade(since, IslandMotion.fade.duration)
                    black = fade(since, NotchcastTheme.Motion.launcherExit)
                } else if step.launcher {
                    content = 0
                    black = 0
                }
                frame += 1
                try write(frame: frame, into: folder) { graphics in
                    drawStage(graphics, shape: shape, launcher: step.launcher ? launcher : nil,
                              launcherFrame: panel.launcherFrame(height: launcherHeight), island: { graphics in
                        graphics.translateBy(x: panel.frame.minX, y: panel.frame.minY)
                        let path = outline.path
                        graphics.setFillColor(NSColor.black.withAlphaComponent(black).cgColor)
                        graphics.addPath(path)
                        graphics.fillPath()
                        graphics.addPath(path)
                        graphics.clip()
                        if let band = panel.cameraBand {
                            graphics.setFillColor(NSColor.black.cgColor)
                            graphics.fill(band)
                        }
                        guard content > 0, let layer = surface.layer else { return }
                        graphics.setAlpha(content * black)
                        graphics.beginTransparencyLayer(auxiliaryInfo: nil)
                        layer.displayIfNeeded()
                        layer.render(in: graphics)
                        graphics.endTransparencyLayer()
                    })
                }
                time += 1 / fps
            }
            previous = settled
        }
        return frame
    }

    static func fade(_ time: TimeInterval, _ duration: TimeInterval) -> CGFloat {
        CGFloat(min(1, max(0, time / duration)))
    }

    /// The gallery's sample states; a timer counts from the moment it started on the stage, not from the render.
    static func closedState(_ key: String, timerElapsed: TimeInterval) -> IslandClosedState {
        let timer = IslandActivity(kind: .timer, title: "Tea timer",
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
