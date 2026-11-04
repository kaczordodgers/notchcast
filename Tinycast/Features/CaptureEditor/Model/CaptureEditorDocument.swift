import Foundation
import Observation

@MainActor
@Observable
final class CaptureEditorDocument {
    struct TextEdit: Equatable {
        let id: UUID
        let origin: CGPoint
        var string: String
    }

    private enum Drag {
        case creating(id: UUID, start: CGPoint)
        case moving(CaptureEditorMark, start: CGPoint)
        case resizing(CaptureEditorMark, handle: CaptureEditorMark.Handle)
    }

    let size: CGSize
    let markScale: CGFloat
    private(set) var marks: [CaptureEditorMark] = []
    private(set) var selection: UUID?
    private(set) var tool: CaptureEditorTool = .arrow
    private(set) var color: CaptureEditorMark.Color = .red
    var textEdit: TextEdit?
    @ObservationIgnored private let textSize: (String) -> CGSize
    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored private var dragStartMarks: [CaptureEditorMark] = []
    private var undoStack: [[CaptureEditorMark]] = []
    private var redoStack: [[CaptureEditorMark]] = []

    init(size: CGSize, markScale: CGFloat = 1, textSize: @escaping (String) -> CGSize) {
        self.size = size
        self.markScale = markScale
        self.textSize = textSize
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selected: CaptureEditorMark? { marks.first { $0.id == selection } }

    func pick(_ tool: CaptureEditorTool) {
        finishGesture()
        commitText()
        if self.tool != tool { selection = nil }
        self.tool = tool
    }

    func pick(_ color: CaptureEditorMark.Color) {
        finishGesture()
        self.color = color
        guard let index = marks.firstIndex(where: { $0.id == selection }), marks[index].color != color else { return }
        let before = marks
        marks[index].color = color
        record(before)
    }

    func pressed(at point: CGPoint, slack: CGFloat) {
        finishGesture()
        commitText()
        dragStartMarks = marks
        if let selected, let grabbed = selected.handles.first(where: {
            hypot($0.point.x - point.x, $0.point.y - point.y) <= slack
        }) {
            drag = .resizing(selected, handle: grabbed.handle)
            return
        }
        if let hit = marks.last(where: { $0.hits(point, slack: slack, markScale: markScale, textSize: textSize) }) {
            selection = hit.id
            if tool == .text, case .text(let origin, let string) = hit.shape {
                textEdit = TextEdit(id: hit.id, origin: origin, string: string)
            } else {
                drag = .moving(hit, start: point)
            }
            return
        }
        selection = nil
        if tool == .text {
            textEdit = TextEdit(id: UUID(), origin: point, string: "")
        } else {
            drag = .creating(id: UUID(), start: point)
        }
    }

    func dragged(to point: CGPoint) {
        switch drag {
        case .creating(let id, let start):
            guard hypot(point.x - start.x, point.y - start.y) >= 4 else {
                marks.removeAll { $0.id == id }
                selection = nil
                return
            }
            let box = CaptureEditorMark.box(start, point)
            let shape: CaptureEditorMark.Shape
            switch tool {
            case .arrow: shape = .arrow(from: start, to: point)
            case .rectangle: shape = .rectangle(box)
            case .ellipse: shape = .ellipse(box)
            case .blur: shape = .blur(box)
            case .text: return
            }
            let mark = CaptureEditorMark(id: id, shape: shape, color: color)
            if let index = marks.firstIndex(where: { $0.id == id }) { marks[index] = mark } else { marks.append(mark) }
            selection = id
        case .moving(let original, let start):
            replace(original.moved(by: CGSize(width: point.x - start.x, height: point.y - start.y)))
        case .resizing(let original, let handle): replace(original.resized(handle, to: point))
        case nil: break
        }
    }

    func released() { finishGesture() }

    func commitText() {
        guard let edit = textEdit else { return }
        textEdit = nil
        let before = marks
        let string = edit.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = marks.firstIndex(where: { $0.id == edit.id }) {
            if string.isEmpty {
                marks.remove(at: index)
                selection = nil
            } else {
                marks[index].shape = .text(origin: edit.origin, string: string)
            }
        } else if !string.isEmpty {
            marks.append(CaptureEditorMark(id: edit.id, shape: .text(origin: edit.origin, string: string), color: color))
            selection = edit.id
        }
        record(before)
    }

    func cancelText() { textEdit = nil }

    func deleteSelected() {
        finishGesture()
        guard let selection else { return }
        let before = marks
        marks.removeAll { $0.id == selection }
        self.selection = nil
        record(before)
    }

    func undo() {
        finishGesture()
        commitText()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(marks)
        marks = previous
        dropStaleSelection()
    }

    func redo() {
        finishGesture()
        commitText()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(marks)
        marks = next
        dropStaleSelection()
    }

    private func replace(_ mark: CaptureEditorMark) {
        guard let index = marks.firstIndex(where: { $0.id == mark.id }) else { return }
        marks[index] = mark
    }

    private func finishGesture() {
        guard drag != nil else { return }
        drag = nil
        record(dragStartMarks)
        dragStartMarks = []
    }

    private func record(_ before: [CaptureEditorMark]) {
        guard before != marks else { return }
        undoStack.append(before)
        redoStack.removeAll()
    }

    private func dropStaleSelection() {
        if let selection, !marks.contains(where: { $0.id == selection }) { self.selection = nil }
    }
}
