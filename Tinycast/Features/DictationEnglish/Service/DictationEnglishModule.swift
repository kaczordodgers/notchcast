import Foundation

@MainActor
final class DictationEnglishModule: NotchcastModule {
    private let register: (@escaping @MainActor () -> Void) -> UUID
    private let remove: (UUID) -> Void
    private let toggle: () -> Void
    private let onStop: () -> Void
    private var registration: UUID?

    init(register: @escaping (@escaping @MainActor () -> Void) -> UUID,
         remove: @escaping (UUID) -> Void, toggle: @escaping () -> Void,
         onStop: @escaping () -> Void = {}) {
        self.register = register
        self.remove = remove
        self.toggle = toggle
        self.onStop = onStop
    }

    func start() {
        guard registration == nil else { return }
        registration = register { [weak self] in
            guard let self, registration != nil else { return }
            toggle()
        }
    }

    func stop() {
        if let registration { remove(registration); onStop() }
        registration = nil
    }

    isolated deinit { stop() }
}
