#if DEBUG
import AppKit
import ImageIO
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

/// Debug only: the closed island's motion as PNG frames on a fixed stage, for comparing designs without a live
/// install. Every look is a real `IslandPanel` laid out offscreen (its mask path and its closed content); the motion
/// between looks evaluates the curves the code uses: the island's CA springs (`IslandMotion`), CA's linear opacity
/// fades, SwiftUI's ease-out content swap, Orion's sway and Damian Tools' analyser on a
/// virtual clock. Run through `notchcast/gallery/stage.sh`.
@MainActor
enum IslandMotionStage {
    static func runIfRequested(_ core: AppCore) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["NOTCHCAST_MOTION_STAGE"],
              let launcher = environment["NOTCHCAST_MOTION_LAUNCHER"] else { return false }
        Task { @MainActor in
            do {
                try await render(into: URL(filePath: directory), launcher: URL(filePath: launcher))
                print("stage: done")
                exit(0)
            } catch {
                print("stage: failed: \(error)")
                exit(1)
            }
        }
        return true
    }

    static let fps = 25.0
    static let stage = CGSize(width: 800, height: 520)

    private static func render(into directory: URL, launcher: URL) async throws {
        guard let source = CGImageSourceCreateWithURL(launcher as CFURL, nil),
              let launcherImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw StageFailure.message("no launcher image at \(launcher.path)")
        }
        for mba in [true, false] {
            let shape = Shape(mba: mba)
            let looks = LookCache(shape: shape)
            for scenario in Scenario.all where mba ? scenario.name != "visualizers" : true {
                let folder = directory.appending(path: "\(scenario.name)-\(shape.suffix)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let player = try await Player(scenario: scenario, shape: shape, looks: looks, launcher: launcherImage)
                let count = Int((scenario.duration * fps).rounded(.up))
                for index in 0..<count {
                    let image = try player.frame(at: Double(index) / fps)
                    try write(image, to: folder.appending(path: String(format: "frame-%04d.png", index + 1)))
                }
                print("stage: \(scenario.name)-\(shape.suffix) \(count) frames")
            }
        }
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw StageFailure.message("cannot write \(url.path)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StageFailure.message("cannot write \(url.path)") }
    }

    enum StageFailure: Error { case message(String) }
}

// MARK: The stage

extension IslandMotionStage {
    struct Shape {
        let mba: Bool
        var suffix: String { mba ? "mba" : "ext" }
        var display: CGRect { CGRect(x: 0, y: 0, width: mba ? 1470 : 1920, height: mba ? 956 : 1080) }
        /// The gallery's measured MacBook Air cutout.
        var notch: CGRect? { mba ? CGRect(x: display.midX - 92, y: display.maxY - 32, width: 184, height: 32) : nil }
        var menuBar: CGFloat { mba ? 37 : 24 }
    }

    /// One closed state as the real panel draws it, in the panel's own coordinates (y up).
    struct Look {
        let path: CGPath
        let content: CGImage
        let body: CGRect
        /// Where the playing song's bars sit, found by comparing the playing and paused renders.
        let bars: CGRect?
    }

    /// What a look shows; the timer's value comes from its second on the scenario clock.
    enum Content: Hashable {
        case idle, music, message, longMessage, timerEnd
        case timer(second: Int)
        case timerAndMusic(second: Int)
    }

    @MainActor
    final class LookCache {
        let shape: Shape
        private(set) var panelFrame = CGRect.zero
        private var cache: [Content: Look] = [:]

        init(shape: Shape) { self.shape = shape }

        func look(_ content: Content) async throws -> Look {
            if let look = cache[content] { return look }
            let playing = try await render(content, playing: true)
            var bars: CGRect?
            if content.hasMusic {
                let paused = try await render(content, playing: false)
                bars = IslandMotionStage.barsRect(playing.content, paused.content)
                let look = Look(path: paused.path, content: paused.content, body: paused.body, bars: bars)
                cache[content] = look
                return look
            }
            cache[content] = playing
            return playing
        }

        private func render(_ content: Content, playing: Bool) async throws -> Look {
            let panel = IslandPanel(screenFrame: shape.display, hardwareNotch: shape.notch)
            panel.setContent(open: AnyView(EmptyView()), closed: content.state(playing: playing),
                             header: AnyView(EmptyView()))
            for _ in 0..<4 {
                panel.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
            }
            panel.setOpen(false, animated: false)
            guard let surface = panel.contentView, surface.subviews.count == 2,
                  let path = (surface.layer?.mask as? CAShapeLayer)?.path,
                  let layer = surface.subviews[1].layer else {
                throw StageFailure.message("no closed host for \(content)")
            }
            let size = surface.bounds.size
            let context = IslandMotionStage.context(size)
            // The island is always dark; as GalleryCapture does, a caching display pass makes the host draw.
            let dark = NSAppearance(named: .darkAqua)
            panel.appearance = dark
            dark?.performAsCurrentDrawingAppearance {
                surface.layoutSubtreeIfNeeded()
                surface.displayIfNeeded()
                if let cached = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) {
                    surface.cacheDisplay(in: surface.bounds, to: cached)
                }
                layer.displayIfNeeded()
                // The hosting view is flipped; its layer renders top down.
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                layer.render(in: context)
            }
            guard let image = context.makeImage() else { throw StageFailure.message("no image for \(content)") }
            let lit = IslandMotionStage.pixels(image).enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count
            print("stage: look \(shape.suffix) \(content) playing=\(playing) lit=\(lit)")
            if let looks = ProcessInfo.processInfo.environment["NOTCHCAST_MOTION_LOOKS"] {
                try FileManager.default.createDirectory(atPath: looks, withIntermediateDirectories: true)
                try IslandMotionStage.write(image, to: URL(filePath: looks)
                    .appending(path: "\(shape.suffix)-\(content)-\(playing).png"))
            }
            panelFrame = panel.frame
            let body = panel.closedBodyFrame.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            panel.close()
            return Look(path: path, content: image, body: body, bars: nil)
        }
    }

    static func context(_ size: CGSize, opaque: Bool = false) -> CGContext {
        let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
        let context = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: alpha.rawValue)!
        context.scaleBy(x: 2, y: 2)
        return context
    }

    /// The bars are the only pixels a playing still and a paused still differ in.
    static func barsRect(_ playing: CGImage, _ paused: CGImage) -> CGRect? {
        let a = pixels(playing), b = pixels(paused)
        let width = playing.width, height = playing.height
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let difference = (0..<4).map { abs(Int(a[offset + $0]) - Int(b[offset + $0])) }.max() ?? 0
                guard difference > 24 else { continue }
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard maxX >= 0 else { return nil }
        let bars = NotchcastTheme.Visualizer.self
        let barsWidth = CGFloat(bars.Orion.count) * bars.Orion.width + CGFloat(bars.Orion.count - 1) * bars.Orion.gap
        let midY = CGFloat(height) / 2 - CGFloat(minY + maxY + 1) / 4
        return CGRect(x: CGFloat(maxX + 1) / 2 - barsWidth, y: midY - bars.height / 2,
                      width: barsWidth, height: bars.height)
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }
}

extension IslandMotionStage.Content {
    var hasMusic: Bool {
        switch self {
        case .music, .timerAndMusic: true
        default: false
        }
    }

    /// SAME-DATA.md, built through the controller's own ranking.
    @MainActor func state(playing: Bool) -> IslandClosedState {
        let track = IslandTrack(title: "Teardrop", artist: "Massive Attack", artwork: IslandMotionStage.cover,
                                isPlaying: playing)
        func tea(_ second: Int) -> IslandActivity {
            IslandActivity(kind: .timer, title: "Tea timer", endDate: Date().addingTimeInterval(Double(299 - second)))
        }
        func message(_ text: String, symbol: String?, detail: String? = nil) -> IslandMessage {
            IslandMessage(id: UUID(), tone: .neutral, text: text, isProgress: false, onCancel: nil, detail: detail,
                          symbol: symbol)
        }
        switch self {
        case .idle: return .idle
        case .music: return IslandController.closedState(message: nil, activities: [], track: track)
        case .message:
            return IslandController.closedState(message: message("AirPods: Connected", symbol: "headphones"),
                                                activities: [], track: nil)
        case .longMessage:
            return IslandController.closedState(
                message: message("Couldn't paste some dictation into the app", symbol: nil,
                                 detail: "The text is on the clipboard instead"), activities: [], track: nil)
        case .timer(let second): return IslandController.closedState(message: nil, activities: [tea(second)], track: nil)
        case .timerAndMusic(let second):
            return IslandController.closedState(message: nil, activities: [tea(second)], track: track)
        case .timerEnd: return IslandClosedState(main: .card(IslandCard(kind: .timerEnd, title: "Tea timer", action: {})))
        }
    }
}

extension IslandMotionStage {
    /// SAME-DATA.md's cover: a flat #2F3E46 square with a centred #F4A261 circle half its width.
    static let cover = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
        NSColor(srgbRed: 0x2F / 255, green: 0x3E / 255, blue: 0x46 / 255, alpha: 1).setFill()
        rect.fill()
        NSColor(srgbRed: 0xF4 / 255, green: 0xA2 / 255, blue: 0x61 / 255, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: rect.width / 4, dy: rect.height / 4)).fill()
        return true
    }
}
#endif
