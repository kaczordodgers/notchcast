import Observation

@MainActor @Observable
final class BrightnessDisplayRowState {
    private(set) var failed = false
    private var pending: Double?
    var display: BrightnessDisplay
    @ObservationIgnored private let controller: BrightnessController
    @ObservationIgnored private var write: Task<Void, Never>?

    init(display: BrightnessDisplay, controller: BrightnessController) {
        self.display = display
        self.controller = controller
    }

    var value: Double {
        get { pending ?? controller.level(of: display.id)?.value ?? display.level.value }
        set {
            pending = newValue
            write?.cancel()
            let id = display.id
            write = Task { [weak self, controller] in
                let result = await controller.set(newValue, for: id)
                guard !Task.isCancelled, let self else { return }
                failed = result == nil
                pending = nil
                write = nil
            }
        }
    }

    func update(_ display: BrightnessDisplay) {
        if self.display.level != display.level { failed = false }
        self.display = display
    }

    func cancel() {
        write?.cancel()
        write = nil
        pending = nil
    }
}
