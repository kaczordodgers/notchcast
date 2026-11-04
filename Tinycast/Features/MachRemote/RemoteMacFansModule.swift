import Foundation

@MainActor
final class RemoteMacFansModule: NotchcastModule {
    private(set) var isRunning = false
    private let preferences: NotchcastPreferences
    private let runner: MachSSH.Runner
    private let post: @MainActor (String) -> Void
    private var task: Task<Void, Never>?
    private var operation = UUID()

    init(preferences: NotchcastPreferences, runner: @escaping MachSSH.Runner,
         post: @escaping @MainActor (String) -> Void) {
        self.preferences = preferences
        self.runner = runner
        self.post = post
    }

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        operation = UUID()
        task?.cancel()
        task = nil
    }

    func set(_ mode: FanControl.Mode) {
        guard isRunning, preferences.isOn(.machRemote), preferences.isOn(.remoteMacFans), task == nil else { return }
        let address = preferences.remoteMacAddress
        let ssh = MachSSH(address: address, runner: runner)
        let identity = UUID()
        operation = identity
        task = Task { [weak self] in
            guard let self else { return }
            defer { if operation == identity { task = nil } }
            do {
                try Task.checkCancellation()
                let command = "exec /usr/bin/sudo -n " + MachSSH.quote(RootContract.helperPath) +
                    " " + MachSSH.quote(mode.command.rawValue)
                let result = try await ssh.run(command)
                guard accepts(identity, address: address) else { return }
                if result.status != 0 || result.output != "ok\n" {
                    post(String(localized: "Unable to set the remote Mac fans."))
                }
            } catch {
                guard accepts(identity, address: address), !(error is CancellationError) else { return }
                post(String(localized: "Unable to set the remote Mac fans."))
            }
        }
    }

    private func accepts(_ identity: UUID, address: String) -> Bool {
        !Task.isCancelled && operation == identity && isRunning &&
            preferences.isOn(.machRemote) && preferences.isOn(.remoteMacFans) &&
            preferences.remoteMacAddress == address
    }

    func waitUntilIdle() async { await task?.value }
}
