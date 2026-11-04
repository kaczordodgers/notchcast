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
        guard valid(frame), !annotations.contains(where: { $0.id == id }) else { return nil }
        history.append(annotations)
        annotations.append(Annotation(id: id, tool: tool, frame: frame, text: text))
        selection = id
        return id
    }

    mutating func moveSelected(by offset: CGSize) {
        guard offset.width.isFinite, offset.height.isFinite,
              let mark = annotations.first(where: { $0.id == selection }) else { return }
        resizeSelected(to: mark.frame.offsetBy(dx: offset.width, dy: offset.height))
    }

    mutating func resizeSelected(to frame: CGRect) {
        guard valid(frame), let index = annotations.firstIndex(where: { $0.id == selection }),
              annotations[index].frame != frame else { return }
        history.append(annotations)
        annotations[index].frame = frame
    }

    mutating func undo() {
        guard let previous = history.popLast() else { return }
        annotations = previous
        select(selection)
    }

    private func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite &&
            frame.height.isFinite && frame.width > 0 && frame.height > 0
    }
}
