import Observation

@MainActor
final class DictationTriggerModule: NotchcastModule {
    private let paused: () -> Bool
    private let available: () -> Bool
    private let reserve: (Bool) -> Void
    private let configure: (Bool, Bool) -> Void
    private let teardown: () -> Void
    private var enabled = false

    init(available: @escaping () -> Bool, paused: @escaping () -> Bool, reserve: @escaping (Bool) -> Void,
         configure: @escaping (Bool, Bool) -> Void, teardown: @escaping () -> Void) {
        self.paused = paused
        self.available = available
        self.reserve = reserve
        self.configure = configure
        self.teardown = teardown
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        observeRecording()
    }

    func stop() { shutdown() }
    func stopForTermination(_ phase: NotchcastTerminationPhase) async { if phase == .beforeSettingsBackup { shutdown() } }

    private func shutdown() {
        guard enabled else { return }
        enabled = false
        teardown()
        reserve(false)
    }

    private func observeRecording() {
        guard enabled else { return }
        withObservationTracking {
            let available = available()
            reserve(available)
            configure(available, paused())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeRecording() }
        }
    }
}
