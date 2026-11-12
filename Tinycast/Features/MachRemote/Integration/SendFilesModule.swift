import Foundation

@MainActor
final class SendFilesModule: NotchcastModule {
    private(set) var coordinator: SendFilesCoordinator?
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

    func send(_ urls: [URL]) {
        guard isRunning, preferences.isEnabled(.sendFiles) else { return }
        guard coordinator?.isRunning != true else { return }
        let shell = MachRemoteShell(ssh: MachSSH(address: preferences.remoteMacAddress, runner: runner))
        coordinator = SendFilesCoordinator(shell: shell, post: post)
        coordinator?.sendFinderSelection(urls)
    }
}
