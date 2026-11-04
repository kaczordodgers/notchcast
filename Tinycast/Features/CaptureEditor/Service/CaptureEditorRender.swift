import CoreGraphics
import CoreText
import Foundation

enum CaptureEditorRender {
    enum Failure: Error { case bitmap }

    static func flatten(_ document: CaptureEditorDocument) throws -> CGImage {
        let image = document.image
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = bitmap(width: image.width, height: image.height, space: space) else {
            throw Failure.bitmap
        }
        context.draw(image, in: bounds)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        for mark in document.annotations {
            context.saveGState()
            defer { context.restoreGState() }
            context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.setLineWidth(3)
            let box = mark.frame
            switch mark.tool {
            case .rectangle: context.stroke(box)
            case .ellipse: context.strokeEllipse(in: box)
            case .arrow:
                guard let arrow = mark.arrow else { continue }
                let end = arrow.to
                let angle = atan2(end.y - arrow.from.y, end.x - arrow.from.x)
                context.move(to: arrow.from)
                context.addLine(to: end)
                context.strokePath()
                context.move(to: end)
                context.addLine(to: CGPoint(x: end.x - 12 * cos(angle - .pi / 6),
                                           y: end.y - 12 * sin(angle - .pi / 6)))
                context.addLine(to: CGPoint(x: end.x - 12 * cos(angle + .pi / 6),
                                           y: end.y - 12 * sin(angle + .pi / 6)))
                context.closePath()
                context.fillPath()
            case .text:
                context.clip(to: box)
                context.translateBy(x: box.minX, y: box.minY + 24)
                context.scaleBy(x: 1, y: -1)
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String):
                        CTFontCreateWithName("Helvetica" as CFString, 24, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                        CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                ]
                CTLineDraw(CTLineCreateWithAttributedString(
                    NSAttributedString(string: mark.text, attributes: attributes)), context)
            case .blur:
                let area = box.intersection(bounds).integral.intersection(bounds)
                guard !area.isNull, !area.isEmpty else { continue }
                guard let crop = image.cropping(to: area),
                      let small = bitmap(width: max(1, Int(area.width / 12)),
                                         height: max(1, Int(area.height / 12)), space: space) else {
                    throw Failure.bitmap
                }
                small.interpolationQuality = .high
                small.draw(crop, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
                guard let mosaic = small.makeImage() else { throw Failure.bitmap }
                context.clip(to: box)
                context.interpolationQuality = .none
                context.translateBy(x: area.minX, y: area.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(mosaic, in: CGRect(origin: .zero, size: area.size))
            }
        }
        guard let result = context.makeImage() else { throw Failure.bitmap }
        return result
    }

    private static func bitmap(width: Int, height: Int, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
