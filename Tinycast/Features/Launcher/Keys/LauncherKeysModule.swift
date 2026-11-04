@MainActor
final class LauncherKeysModule: NotchcastModule {
    private(set) var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }
}
