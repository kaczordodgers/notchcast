@MainActor
final class DisplayBrightnessModule: NotchcastModule {
    let controller = BrightnessController()
    private var transition: Task<Void, Never>?

    func start() { NotchcastHost.current.refreshNotchcastCommands(); setRunning(true) }
    func stop() { NotchcastHost.current.refreshNotchcastCommands(); setRunning(false) }

    private func setRunning(_ running: Bool) {
        let previous = transition
        previous?.cancel()
        transition = Task { [controller] in
            await previous?.value
            guard !Task.isCancelled else { return }
            if running { await controller.start() } else { await controller.stop() }
        }
    }

    isolated deinit { transition?.cancel() }
}
