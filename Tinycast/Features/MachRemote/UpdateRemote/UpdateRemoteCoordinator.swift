import Foundation
import Observation

@MainActor
@Observable
final class UpdateRemoteCoordinator {
    private(set) var isRunning = false
    private(set) var progress = UpdateRemoteProgress()
    private(set) var result: UpdateRemoteProgress.Result?
    @ObservationIgnored private let runner: any RemoteShellRunning
    @ObservationIgnored private let scriptPath: String
    @ObservationIgnored private let post: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var operation = UUID()

    init(runner: any RemoteShellRunning, scriptPath: String = "", post: @escaping @MainActor (String) -> Void) {
        self.runner = runner
        self.scriptPath = scriptPath
        self.post = post
    }

    func start() {
        guard !isRunning else { return }
        guard MachSSH.isValid(runner.sshAlias), !scriptPath.isEmpty else {
            result = .unreachable
            post((MachSSH.isValid(runner.sshAlias) ? MachSSH.ConfigurationError.path : .address).localizedDescription)
            return
        }
        isRunning = true
        progress = UpdateRemoteProgress()
        result = nil
        let identity = UUID()
        operation = identity
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let response = try await runner.ssh(command: "exec " + MachSSH.remotePath(scriptPath),
                    options: ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]) { [weak self] output in
                    guard let self, self.operation == identity, !Task.isCancelled else { return }
                    for line in output.split(separator: "\n") {
                        self.progress.consume(String(line))
                        self.post(String(line))
                    }
                }
                guard operation == identity else { return }
                if Task.isCancelled { finish(.cancelled) } else { finish(progress.result(status: response.status)) }
            } catch {
                guard operation == identity else { return }
                finish(Task.isCancelled || error is CancellationError ? .cancelled : .failed(step: progress.step))
            }
        }
    }

    func stop() { cancel() }

    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        operation = UUID()
        finish(.cancelled)
    }

    private func finish(_ value: UpdateRemoteProgress.Result) {
        result = value
        isRunning = false
        task = nil
        switch value {
        case .updated: post(String(localized: "Remote Mac updated.", table: "UpdateRemote"))
        case .nothingToDo: post(String(localized: "Remote Mac is up to date.", table: "UpdateRemote"))
        case .cancelled: post(String(localized: "Stopped following the remote update.", table: "UpdateRemote"))
        case .unreachable: post(String(localized: "Unable to reach the remote Mac.", table: "UpdateRemote"))
        case .failed(let step):
            post(String(localized: "Remote update failed.", table: "UpdateRemote") + (step.map { " " + $0 } ?? ""))
        }
    }
}
