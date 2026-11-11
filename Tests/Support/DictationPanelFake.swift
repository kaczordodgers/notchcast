@MainActor final class DictationPanelController {
    enum Phase { case listening, transcribing }
    @MainActor final class State { var phase = Phase.listening; var levels: [Float] = [] }
    static weak var latest: DictationPanelController?
    let state = State()
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var isVisible = false
    init() { Self.latest = self }
    func show() { isVisible = true }
    func close() { isVisible = false }
}
