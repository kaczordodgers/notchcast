import Foundation
import Observation

@MainActor
@Observable
final class MachineBackupCoordinator: NotchcastModule {
    private(set) var snapshots: [MachineBackupSnapshot] = []
    private(set) var nodes: [MachineBackupNode] = []
    private(set) var isBusy = false
    private(set) var lastRestoreTarget: URL?
    @ObservationIgnored private let tooling: any MachineBackupTooling
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private var configuration: MachineBackupConfiguration?
    @ObservationIgnored private var operation: Task<Data, Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var running = false

    init(tooling: any MachineBackupTooling, preferences: NotchcastPreferences) {
        self.tooling = tooling
        self.preferences = preferences
    }

    func configure(_ configuration: MachineBackupConfiguration?) throws {
        try configuration?.validate()
        let wasRunning = running
        stop()
        self.configuration = configuration
        running = wasRunning
    }

    func start() { running = true }

    func waitUntilIdle() async { _ = await operation?.result }

    func stop() { shutdown() }
    func stopForTermination(_ phase: NotchcastTerminationPhase) async {
        guard phase == .beforeRootDrain else { return }
        shutdown()
        await waitUntilIdle()
    }

    private func shutdown() {
        running = false
        generation = UUID()
        operation?.cancel()
        snapshots = []
        nodes = []
        lastRestoreTarget = nil
    }

    func runNow() async throws {
        let configuration = try configured(for: .backupRunNow)
        _ = try await perform(try MachineBackupPolicy.runNow(configuration), feature: .backupRunNow)
    }

    func refreshSnapshots() async throws {
        let configuration = try configured(for: .backupBrowseRestore)
        let data = try await perform(try MachineBackupPolicy.snapshots(configuration), feature: .backupBrowseRestore)
        snapshots = try MachineBackupPolicy.decodeSnapshots(data, host: configuration.host)
        nodes = []
    }

    func browse(snapshot: String, path: String = "/") async throws {
        let configuration = try configured(for: .backupBrowseRestore)
        let request = try MachineBackupPolicy.browse(configuration, snapshot: snapshot, path: path)
        let data = try await perform(request, feature: .backupBrowseRestore)
        nodes = try MachineBackupPolicy.decodeNodes(data)
    }

    func restore(snapshot: String, path: String, target: URL) async throws {
        let configuration = try configured(for: .backupBrowseRestore)
        let request = try MachineBackupPolicy.restore(configuration, snapshot: snapshot, path: path, target: target)
        _ = try await perform(request, feature: .backupBrowseRestore)
        lastRestoreTarget = target
    }

    private func configured(for feature: NotchcastFeature) throws -> MachineBackupConfiguration {
        guard running, preferences.isOn(feature) else { throw MachineBackupFailure.disabled }
        guard let configuration else { throw MachineBackupFailure.configuration }
        return configuration
    }

    private func perform(_ request: MachineBackupRequest, feature: NotchcastFeature) async throws -> Data {
        guard !isBusy else { throw MachineBackupFailure.busy }
        try Task.checkCancellation()
        generation = UUID()
        let identity = generation
        let tooling = tooling
        let task = Task { try await tooling.run(request) }
        operation = task
        isBusy = true
        observe(feature, identity: identity)
        defer {
            operation = nil
            isBusy = false
        }
        return try await withTaskCancellationHandler {
            let data = try await task.value
            try Task.checkCancellation()
            guard !task.isCancelled, running, generation == identity, preferences.isOn(feature) else {
                throw CancellationError()
            }
            return data
        } onCancel: {
            task.cancel()
        }
    }

    private func observe(_ feature: NotchcastFeature, identity: UUID) {
        guard isBusy, generation == identity else { return }
        withObservationTracking {
            if !preferences.isOn(feature) { operation?.cancel() }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe(feature, identity: identity) }
        }
    }
}
