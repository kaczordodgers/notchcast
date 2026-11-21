import CoreGraphics

/// Where a scrolling capture is; the one command starts it, finishes it, or is ignored.
enum ScrollingCapturePhase: Equatable, Sendable {
    case idle, selecting, capturing, finishing

    enum Command: Equatable, Sendable { case start, finish, ignore }

    var command: Command {
        switch self {
        case .idle: .start
        case .capturing: .finish
        case .selecting, .finishing: .ignore
        }
    }

    /// The stitched height in at most four characters for the pill, rounded down so it never overstates.
    static func heightText(_ height: Int) -> String {
        let pixels = max(0, height)
        return switch pixels {
        case ..<1_000: "\(pixels)"
        case ..<10_000 where pixels % 1_000 >= 100: "\(pixels / 1_000).\(pixels % 1_000 / 100)k"
        default: "\(pixels / 1_000)k"
        }
    }
}

/// The scrolled area: one display, in Quartz global points on whole pixels, so no frame is resampled.
struct ScrollingCaptureRegion: Equatable, Sendable {
    let displayID: UInt32
    let rect: CGRect
    let scale: CGFloat

    /// A dragged area as it is, a clicked window as its frame, a display whole; nil off a single display.
    init?(_ request: ScreenshotRequest, displays: [ScreenshotFrozenDisplay], windows: [ScreenshotWindow]) {
        let wanted: CGRect
        let display: ScreenshotFrozenDisplay?
        switch request {
        case .rect(let rect):
            guard ScreenshotRequest.isValid(rect: rect) else { return nil }
            wanted = rect
            display = displays.first { $0.frame.contains(rect) }
        case .window(let id):
            guard let frame = windows.first(where: { $0.id == id })?.frame else { return nil }
            wanted = frame
            display = displays.first { $0.frame.contains(frame) }
        case .display(let id):
            display = displays.first { $0.id == id }
            wanted = display?.frame ?? .null
        }
        guard let display else { return nil }
        let scale = display.scale
        let local = wanted.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let pixels = CGRect(x: local.minX * scale, y: local.minY * scale,
                            width: local.width * scale, height: local.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: display.image.width, height: display.image.height))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1, scale > 0 else { return nil }
        displayID = display.id
        self.scale = scale
        rect = CGRect(x: pixels.minX / scale + display.frame.minX, y: pixels.minY / scale + display.frame.minY,
                      width: pixels.width / scale, height: pixels.height / scale)
    }
}
