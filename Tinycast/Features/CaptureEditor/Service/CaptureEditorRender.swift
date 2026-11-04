import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureEditorRender {
    enum Failure: Error { case rendering, encoding }

    @concurrent
    static func png(_ image: CaptureEditorImage, marks: [CaptureEditorMark]) async throws -> Data {
        try Task.checkCancellation()
        let flat = try flatten(image, marks: marks)
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encoding
        }
        let properties = [kCGImagePropertyDPIWidth: image.scale.width * 72,
                          kCGImagePropertyDPIHeight: image.scale.height * 72] as CFDictionary
        CGImageDestinationAddImage(encoder, flat, properties)
        guard CGImageDestinationFinalize(encoder) else { throw Failure.encoding }
        try Task.checkCancellation()
        return data as Data
    }

    static func flatten(_ image: CaptureEditorImage, marks: [CaptureEditorMark]) throws -> CGImage {
        let width = image.pixels.width, height = image.pixels.height
        guard let context = bitmap(width: width, height: height, space: image.pixels.colorSpace) else {
            throw Failure.rendering
        }
        context.draw(image.pixels, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: image.scale.width, y: -image.scale.height)
        for mark in marks {
            try draw(mark, over: image, in: context)
        }
        guard let flat = context.makeImage() else { throw Failure.rendering }
        return flat
    }

    static func textSize(_ string: String, markScale: CGFloat) -> CGSize {
        let text = attributedText(string, color: .white, markScale: markScale)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(text),
            CFRange(), nil, CGSize(width: 10_000, height: 10_000), nil)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private static func bitmap(width: Int, height: Int, space: CGColorSpace?) -> CGContext? {
        if let space, space.model == .rgb,
           let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
               bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            return context
        }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func draw(_ mark: CaptureEditorMark, over image: CaptureEditorImage, in context: CGContext) throws {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color(mark.color))
        context.setFillColor(color(mark.color))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let scale = image.markScale
        switch mark.shape {
        case .arrow(let from, let to): arrow(from: from, to: to, scale: scale, in: context)
        case .rectangle(let rect):
            context.setLineWidth(4 * scale)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: min(6 * scale, rect.width / 2),
                                   cornerHeight: min(6 * scale, rect.height / 2), transform: nil))
            context.strokePath()
        case .ellipse(let rect):
            context.setLineWidth(4 * scale)
            context.strokeEllipse(in: rect)
        case .blur(let rect): try pixelate(rect, of: image, in: context)
        case .text(let origin, let string):
            let size = textSize(string, markScale: scale)
            guard size.width > 0, size.height > 0 else { return }
            context.translateBy(x: origin.x, y: origin.y + size.height)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            let text = attributedText(string, color: mark.color, markScale: scale)
            let rect = CGRect(origin: .zero, size: CGSize(width: size.width + 1, height: size.height))
            let path = CGPath(rect: rect, transform: nil)
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(), path, nil)
            CTFrameDraw(frame, context)
        }
    }

    private static func arrow(from: CGPoint, to: CGPoint, scale: CGFloat, in context: CGContext) {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return }
        let ux = (to.x - from.x) / length, uy = (to.y - from.y) / length
        let head = min(24 * scale, length), half = 11 * head / 24
        let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        context.setLineWidth(5 * scale)
        context.move(to: from)
        context.addLine(to: CGPoint(x: base.x + ux * head * 0.5, y: base.y + uy * head * 0.5))
        context.strokePath()
        context.setLineWidth(3 * scale)
        context.move(to: to)
        context.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
        context.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
        context.closePath()
        context.drawPath(using: .fillStroke)
    }

    private static func pixelate(_ rect: CGRect, of image: CaptureEditorImage, in context: CGContext) throws {
        let scale = image.scale
        let pixels = CGRect(x: rect.minX * scale.width, y: rect.minY * scale.height,
                            width: rect.width * scale.width, height: rect.height * scale.height).integral
            .intersection(CGRect(x: 0, y: 0, width: image.pixels.width, height: image.pixels.height))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1 else { return }
        guard let crop = image.pixels.cropping(to: pixels) else { throw Failure.rendering }
        let columns = max(1, Int(ceil(pixels.width / (10 * scale.width))))
        let rows = max(1, Int(ceil(pixels.height / (10 * scale.height))))
        guard let small = bitmap(width: columns, height: rows, space: image.pixels.colorSpace) else {
            throw Failure.rendering
        }
        small.interpolationQuality = .high
        small.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let mosaic = small.makeImage() else { throw Failure.rendering }
        let area = CGRect(x: pixels.minX / scale.width, y: pixels.minY / scale.height,
                          width: pixels.width / scale.width, height: pixels.height / scale.height)
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.translateBy(x: area.minX, y: area.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(mosaic, in: CGRect(origin: .zero, size: area.size))
    }

    private static func attributedText(_ string: String, color markColor: CaptureEditorMark.Color,
                                       markScale: CGFloat) -> CFAttributedString {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 22 * markScale, nil)!
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color(markColor),
                          kCTStrokeColorAttributeName: CGColor(gray: 0, alpha: 0.55),
                          kCTStrokeWidthAttributeName: -3.0 / 22 * 100] as CFDictionary
        return CFAttributedStringCreate(nil, string as CFString, attributes)!
    }

    private static func color(_ color: CaptureEditorMark.Color) -> CGColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch color {
        case .red: rgb = (255, 69, 58)
        case .yellow: rgb = (255, 214, 10)
        case .green: rgb = (48, 209, 88)
        case .blue: rgb = (64, 156, 255)
        case .white: rgb = (255, 255, 255)
        }
        return CGColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
    }
}
