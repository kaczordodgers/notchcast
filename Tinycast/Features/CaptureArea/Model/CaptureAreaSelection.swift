import Foundation

struct CaptureAreaSelection: Sendable, Equatable {
    let rect: CGRect
    let displayID: UInt32
    let displayFrame: CGRect

    var sourceRect: CGRect {
        rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    static func isValid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
            && rect.size.width >= 1 && rect.size.height >= 1
    }

    static func make(
        from start: CGPoint, to end: CGPoint, displayID: UInt32, displayFrame: CGRect,
        mainDisplayHeight: CGFloat
    ) -> Self? {
        guard mainDisplayHeight.isFinite,
            let rect = appKitRect(from: start, to: end, displayFrame: displayFrame)
        else { return nil }
        return Self(
            rect: quartzRect(rect, mainDisplayHeight: mainDisplayHeight), displayID: displayID,
            displayFrame: quartzRect(displayFrame, mainDisplayHeight: mainDisplayHeight))
    }

    static func appKitRect(
        from start: CGPoint, to end: CGPoint, displayFrame: CGRect
    ) -> CGRect? {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
            displayFrame.width > 0, displayFrame.height > 0
        else { return nil }
        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        ).intersection(displayFrame)
        guard isValid(rect) else { return nil }
        return rect
    }

    private static func quartzRect(_ rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
