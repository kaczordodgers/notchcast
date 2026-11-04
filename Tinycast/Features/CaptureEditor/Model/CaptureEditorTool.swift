import Foundation

enum CaptureEditorTool: String, CaseIterable, Sendable {
    case arrow
    case text
    case rectangle
    case ellipse
    case blur

    var key: String {
        switch self {
        case .arrow: "a"
        case .text: "t"
        case .rectangle: "r"
        case .ellipse: "o"
        case .blur: "b"
        }
    }
}
