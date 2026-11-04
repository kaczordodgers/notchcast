import Observation

@MainActor
final class DictationTriggerModule: NotchcastModule {
    private let paused: () -> Bool
    private let reserve: (Bool) -> Void
    private let configure: (Bool, Bool) -> Void
    private let teardown: () -> Void
    private var enabled = false

    init(paused: @escaping () -> Bool, reserve: @escaping (Bool) -> Void,
         configure: @escaping (Bool, Bool) -> Void, teardown: @escaping () -> Void) {
        self.paused = paused
        self.reserve = reserve
        self.configure = configure
        self.teardown = teardown
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        reserve(true)
        observeRecording()
    }

    func stop() {
        guard enabled else { return }
        enabled = false
        teardown()
        reserve(false)
    }

    private func observeRecording() {
        guard enabled else { return }
        withObservationTracking {
            configure(true, paused())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeRecording() }
        }
    }
}
