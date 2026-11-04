import CoreGraphics
import Foundation

struct CaptureEditorDocument: Sendable {
    enum Tool: String, CaseIterable, Sendable {
        case arrow = "a", text = "t", rectangle = "r", ellipse = "o", blur = "b"
    }

    struct Annotation: Identifiable, Equatable, Sendable {
        let id: UUID
        var tool: Tool
        var frame: CGRect
        var text: String
        var arrow: Arrow?
    }

    struct Arrow: Equatable, Sendable {
        var from: CGPoint
        var to: CGPoint
    }

    let image: CGImage
    private(set) var annotations: [Annotation] = []
    private(set) var selection: UUID?
    private(set) var tool: Tool = .arrow
    private var history: [[Annotation]] = []

    init(image: CGImage) { self.image = image }
    var canUndo: Bool { !history.isEmpty }
    mutating func pick(_ tool: Tool) { self.tool = tool }
    mutating func select(_ id: UUID?) { selection = annotations.first { $0.id == id }?.id }

    @discardableResult
    mutating func add(frame: CGRect, text: String = "", id: UUID = UUID()) -> UUID? {
        if tool == .arrow {
            return arrow(from: frame.origin, to: CGPoint(x: frame.maxX, y: frame.maxY), id: id)
        }
        guard valid(frame), !annotations.contains(where: { $0.id == id }) else { return nil }
        history.append(annotations)
        annotations.append(Annotation(id: id, tool: tool, frame: frame, text: text))
        selection = id
        return id
    }

    @discardableResult
    mutating func arrow(from: CGPoint, to: CGPoint, id: UUID = UUID()) -> UUID? {
        guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite,
              from != to, !annotations.contains(where: { $0.id == id }) else { return nil }
        let frame = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                           width: abs(to.x - from.x), height: abs(to.y - from.y))
        history.append(annotations)
        annotations.append(Annotation(id: id, tool: .arrow, frame: frame, text: "",
                                      arrow: Arrow(from: from, to: to)))
        selection = id
        return id
    }

    mutating func moveSelected(by offset: CGSize) {
        guard offset.width.isFinite, offset.height.isFinite,
              let mark = annotations.first(where: { $0.id == selection }) else { return }
        resizeSelected(to: mark.frame.offsetBy(dx: offset.width, dy: offset.height))
    }

    mutating func resizeSelected(to frame: CGRect) {
        guard let index = annotations.firstIndex(where: { $0.id == selection }),
              valid(frame, arrow: annotations[index].arrow != nil),
              annotations[index].frame != frame else { return }
        history.append(annotations)
        if let arrow = annotations[index].arrow {
            let old = annotations[index].frame
            func transformed(_ point: CGPoint) -> CGPoint {
                CGPoint(x: frame.minX + (old.width == 0 ? 0 : (point.x - old.minX) / old.width * frame.width),
                        y: frame.minY + (old.height == 0 ? 0 : (point.y - old.minY) / old.height * frame.height))
            }
            annotations[index].arrow = Arrow(from: transformed(arrow.from), to: transformed(arrow.to))
        }
        annotations[index].frame = frame
    }

    mutating func undo() {
        guard let previous = history.popLast() else { return }
        annotations = previous
        select(selection)
    }

    private func valid(_ frame: CGRect, arrow: Bool = false) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite &&
            frame.height.isFinite && (arrow
                ? frame.width >= 0 && frame.height >= 0 && (frame.width > 0 || frame.height > 0)
                : frame.width > 0 && frame.height > 0)
    }
}
