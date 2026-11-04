import Foundation
import Observation

@MainActor
@Observable
final class UpdateRemoteCoordinator {
    private(set) var isRunning = false
    private(set) var progress = UpdateRemoteProgress()
    private(set) var result: UpdateRemoteProgress.Result?
    @ObservationIgnored private let runner: any UpdateRemoteShellRunning
    @ObservationIgnored private let scriptPath: String
    @ObservationIgnored private let post: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var operation = UUID()

    init(runner: any UpdateRemoteShellRunning, scriptPath: String = "", post: @escaping @MainActor (String) -> Void) {
        self.runner = runner
        self.scriptPath = scriptPath
        self.post = post
    }

    static func arguments(alias: String, scriptPath: String = "") -> [String]? {
        guard MachSSH.isValid(alias), !scriptPath.isEmpty
        else { return nil }
        return ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "--", alias,
                "exec " + MachSSH.remotePath(scriptPath)]
    }

    func start() {
        guard !isRunning else { return }
        guard let arguments = Self.arguments(alias: runner.sshAlias, scriptPath: scriptPath) else {
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
                let response = try await runner.run("/usr/bin/ssh", arguments: arguments) { [weak self] line in
                    guard let self, self.operation == identity, !Task.isCancelled else { return }
                    self.progress.consume(line)
                    self.post(line)
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
