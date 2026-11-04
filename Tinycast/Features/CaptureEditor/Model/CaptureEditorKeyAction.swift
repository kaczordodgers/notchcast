import Foundation

enum CaptureEditorKeyAction: Equatable, Sendable {
    case tool(CaptureEditorTool)
    case undo
    case redo
    case delete
    case copy
    case close

    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let command = Self(rawValue: 1)
        static let shift = Self(rawValue: 2)
        static let option = Self(rawValue: 4)
        static let control = Self(rawValue: 8)
    }

    static func action(keyCode: UInt16, characters: String?, modifiers: Modifiers) -> Self? {
        let letter = characters?.lowercased()
        if modifiers.isEmpty {
            switch keyCode {
            case 53: return .close
            case 36, 76: return .copy
            case 51, 117: return .delete
            default: return CaptureEditorTool.allCases.first { letter == $0.key }.map(Self.tool)
            }
        }
        if modifiers == .command {
            if letter == "c" { return .copy }
            if letter == "z" { return .undo }
        }
        if modifiers == [.command, .shift], letter == "z" { return .redo }
        return nil
    }
}

extension CaptureEditorDocument {
    func apply(_ action: CaptureEditorKeyAction) {
        switch action {
        case .tool(let tool): pick(tool)
        case .undo: undo()
        case .redo: redo()
        case .delete: deleteSelected()
        case .copy, .close: break
        }
    }
}
