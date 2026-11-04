import Foundation

struct CaptureEditorMark: Identifiable, Equatable, Sendable {
    enum Color: String, CaseIterable, Sendable {
        case red
        case yellow
        case green
        case blue
        case white
    }

    enum Shape: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case blur(CGRect)
        case text(origin: CGPoint, string: String)
    }

    enum Handle: Equatable, Sendable {
        case arrowStart
        case arrowEnd
        case corner(horizontal: Edge, vertical: Edge)

        enum Edge: Sendable { case min, mid, max }
    }

    let id: UUID
    var shape: Shape
    var color: Color

    init(id: UUID = UUID(), shape: Shape, color: Color = .red) {
        self.id = id
        self.shape = shape
        self.color = color
    }

    func bounds(textSize: (String) -> CGSize) -> CGRect {
        switch shape {
        case .arrow(let from, let to): Self.box(from, to)
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect): rect
        case .text(let origin, let string): CGRect(origin: origin, size: textSize(string))
        }
    }

    var handles: [(handle: Handle, point: CGPoint)] {
        switch shape {
        case .arrow(let from, let to): [(.arrowStart, from), (.arrowEnd, to)]
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect):
            Handle.Edge.allPositions.flatMap { horizontal in
                Handle.Edge.allPositions.compactMap { vertical in
                    guard horizontal != .mid || vertical != .mid else { return nil }
                    return (.corner(horizontal: horizontal, vertical: vertical), CGPoint(
                        x: Self.coordinate(horizontal, min: rect.minX, max: rect.maxX),
                        y: Self.coordinate(vertical, min: rect.minY, max: rect.maxY)))
                }
            }
        case .text: []
        }
    }

    func hits(_ point: CGPoint, slack: CGFloat, markScale: CGFloat, textSize: (String) -> CGSize) -> Bool {
        switch shape {
        case .arrow(let from, let to):
            let dx = to.x - from.x, dy = to.y - from.y
            let length = dx * dx + dy * dy
            let fraction = length > 0 ? max(0, min(1, ((point.x - from.x) * dx + (point.y - from.y) * dy) / length)) : 0
            return hypot(point.x - from.x - fraction * dx, point.y - from.y - fraction * dy) <= slack + 2.5 * markScale
        case .rectangle(let rect):
            let tolerance = slack + 2 * markScale
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                && !rect.insetBy(dx: tolerance, dy: tolerance).contains(point)
        case .ellipse(let rect):
            let tolerance = slack + 2 * markScale
            guard rect.width > 0, rect.height > 0 else {
                return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            let dx = (point.x - rect.midX) / (rect.width / 2), dy = (point.y - rect.midY) / (rect.height / 2)
            return abs(hypot(dx, dy) - 1) <= (slack + 2 * markScale) / max(1, min(rect.width, rect.height) / 2)
        case .blur(let rect): return rect.insetBy(dx: -slack, dy: -slack).contains(point)
        case .text: return bounds(textSize: textSize).insetBy(dx: -slack, dy: -slack).contains(point)
        }
    }

    func moved(by delta: CGSize) -> Self {
        var mark = self
        func translated(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + delta.width, y: point.y + delta.height)
        }
        switch shape {
        case .arrow(let from, let to): mark.shape = .arrow(from: translated(from), to: translated(to))
        case .rectangle(let rect): mark.shape = .rectangle(rect.offsetBy(dx: delta.width, dy: delta.height))
        case .ellipse(let rect): mark.shape = .ellipse(rect.offsetBy(dx: delta.width, dy: delta.height))
        case .blur(let rect): mark.shape = .blur(rect.offsetBy(dx: delta.width, dy: delta.height))
        case .text(let origin, let string): mark.shape = .text(origin: translated(origin), string: string)
        }
        return mark
    }

    func resized(_ handle: Handle, to point: CGPoint) -> Self {
        var mark = self
        func resized(_ rect: CGRect) -> CGRect {
            guard case .corner(let horizontal, let vertical) = handle else { return rect }
            let from = CGPoint(x: horizontal == .min ? point.x : rect.minX, y: vertical == .min ? point.y : rect.minY)
            let to = CGPoint(x: horizontal == .max ? point.x : rect.maxX, y: vertical == .max ? point.y : rect.maxY)
            return Self.box(from, to)
        }
        switch shape {
        case .arrow(let from, let to):
            if handle == .arrowStart { mark.shape = .arrow(from: point, to: to) }
            if handle == .arrowEnd { mark.shape = .arrow(from: from, to: point) }
        case .rectangle(let rect): mark.shape = .rectangle(resized(rect))
        case .ellipse(let rect): mark.shape = .ellipse(resized(rect))
        case .blur(let rect): mark.shape = .blur(resized(rect))
        case .text: break
        }
        return mark
    }

    static func box(_ from: CGPoint, _ to: CGPoint) -> CGRect {
        CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
    }

    private static func coordinate(_ edge: Handle.Edge, min: CGFloat, max: CGFloat) -> CGFloat {
        switch edge {
        case .min: min
        case .mid: (min + max) / 2
        case .max: max
        }
    }
}

private extension CaptureEditorMark.Handle.Edge {
    static var allPositions: [Self] { [.min, .mid, .max] }
}
