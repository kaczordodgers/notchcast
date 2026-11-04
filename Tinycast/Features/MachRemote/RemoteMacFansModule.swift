import Foundation

@MainActor
final class RemoteMacFansModule: NotchcastModule {
    private(set) var isRunning = false
    private let preferences: NotchcastPreferences
    private let runner: MachSSH.Runner
    private let post: @MainActor (String) -> Void
    private let changed: @MainActor () -> Void
    private var pendingMode: FanControl.Mode?
    private var task: Task<Void, Never>?
    private var operation = UUID()

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
        operation = UUID()
        task?.cancel()
        task = nil
        pendingMode = nil
        changed()
    }

    func set(_ mode: FanControl.Mode) {
        guard isRunning, preferences.isOn(.machRemote), preferences.isOn(.remoteMacFans) else { return }
        guard task == nil else {
            pendingMode = mode
            return
        }
        let address = preferences.remoteMacAddress
        let ssh = MachSSH(address: address, runner: runner)
        let identity = UUID()
        operation = identity
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if operation == identity {
                    task = nil
                    let next = pendingMode
                    pendingMode = nil
                    if accepts(identity, address: address), let next { set(next) }
                }
            }
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

    func waitUntilIdle() async {
        while let task { await task.value }
    }
}
