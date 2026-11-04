import AppKit

struct CaptureEditorImage: Sendable {
    let pixels: CGImage
    let points: CGSize
    let markScale: CGFloat

    init?(pixels: CGImage, points: CGSize, markScale: CGFloat = 1) {
        guard points.width.isFinite, points.height.isFinite, points.width > 0, points.height > 0,
              markScale.isFinite, markScale > 0 else { return nil }
        self.pixels = pixels
        self.points = points
        self.markScale = markScale
    }

    @MainActor
    init?(_ image: NSImage) {
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(pixels: pixels, points: image.size)
    }

    var scale: CGSize {
        CGSize(width: CGFloat(pixels.width) / points.width, height: CGFloat(pixels.height) / points.height)
    }
}
