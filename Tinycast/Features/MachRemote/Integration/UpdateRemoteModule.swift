import Foundation

@MainActor
final class UpdateRemoteModule: NotchcastModule {
    private(set) var coordinator: UpdateRemoteCoordinator?
    private(set) var isRunning = false
    let preferences: NotchcastPreferences
    let runner: MachSSH.Runner
    let post: @MainActor (String) -> Void
    let changed: @MainActor () -> Void

    init(preferences: NotchcastPreferences, runner: @escaping MachSSH.Runner,
         post: @escaping @MainActor (String) -> Void, changed: @escaping @MainActor () -> Void = {}) {
        self.preferences = preferences
        self.runner = runner
        self.post = post
        self.changed = changed
    }

    func start() {
        isRunning = true
        changed()
    }
    func stop() {
        isRunning = false
        coordinator?.stop()
        changed()
    }

    func update() {
        guard isRunning, preferences.isEnabled(.updateRemote) else { return }
        guard coordinator?.isRunning != true else { return }
        let shell = MachRemoteShell(ssh: MachSSH(address: preferences.remoteMacAddress, runner: runner))
        coordinator = UpdateRemoteCoordinator(runner: MachUpdateRunner(shell: shell),
            scriptPath: preferences.remoteUpdatePath, post: post)
        coordinator?.start()
    }
}
