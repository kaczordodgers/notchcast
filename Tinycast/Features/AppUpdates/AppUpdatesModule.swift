import Foundation
import Observation

@MainActor
@Observable
final class AppUpdatesModule: NotchcastModule {
    private let checkApps: () async throws -> [AppUpdate]
    private var enabled = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    var results: [AppUpdate] = []
    var checking = false

    init(check: @escaping () async throws -> [AppUpdate]) { checkApps = check }
    func start() { enabled = true }
    func stop() { shutdown() }
    func stopForTermination(_ phase: NotchcastTerminationPhase) async { if phase == .beforeMacUpdate { shutdown() } }
    private func shutdown() {
        enabled = false
        generation = UUID()
        task?.cancel()
        task = nil
        checking = false
        results = []
    }

    func check() {
        guard enabled, !checking else { return }
        checking = true
        let identity = generation
        task = Task { [weak self] in
            guard let self else { return }
            let rows = (try? await checkApps()) ?? []
            guard !Task.isCancelled, enabled, generation == identity else { return }
            results = rows
            checking = false
            task = nil
        }
    }
}
