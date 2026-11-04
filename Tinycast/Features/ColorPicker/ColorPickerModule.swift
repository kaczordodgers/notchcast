import Observation

@MainActor
@Observable
final class ColorPickerModule: NotchcastModule {
    var format: ColorPickerFormat {
        didSet { service.format = format }
    }
    private let service: ColorPickerService
    private var enabled = false

    init(service: ColorPickerService = ColorPickerService()) {
        self.service = service
        format = service.format
    }

    func start() { enabled = true }

    func stop() {
        enabled = false
        service.stop()
    }

    func pick(completion: @escaping (ColorPickerService.Outcome) -> Void) {
        service.pick(isEnabled: enabled, completion: completion)
    }
}
