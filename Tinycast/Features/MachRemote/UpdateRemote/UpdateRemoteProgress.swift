import Foundation

struct UpdateRemoteProgress: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case updated, nothingToDo, cancelled, unreachable
        case failed(step: String?)
    }

    private(set) var step: String?
    private(set) var failedSteps: String?
    private var nothingToDo = false

    mutating func consume(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("── ") { step = String(text.dropFirst(3)) }
        if text.hasPrefix("✗ needs attention: ") { failedSteps = String(text.dropFirst(19)) }
        if text == "Nothing to do." { nothingToDo = true }
    }

    func result(status: Int32) -> Result {
        if status == 255 { return .unreachable }
        if status != 0 || failedSteps != nil { return .failed(step: failedSteps ?? step) }
        return nothingToDo ? .nothingToDo : .updated
    }
}
