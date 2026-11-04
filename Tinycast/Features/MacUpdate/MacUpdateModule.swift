import Foundation
import Observation

@MainActor
@Observable
final class MacUpdateModule: NotchcastModule {
    private let service: MacUpdateService
    private var enabled = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    var progress: [MacUpdateService.Progress] = []
    var running = false

    init(service: MacUpdateService) { self.service = service }
    func start() { enabled = true }
    func stop() { enabled = false; cancel(); progress = [] }
    func waitUntilIdle() async { await service.stop() }
    func stopForTermination() async {
        stop()
        await waitUntilIdle()
    }
    func cancel() {
        generation = UUID()
        service.cancel()
        task?.cancel()
        task = nil
        running = false
        progress = progress.map {
            .init(step: $0.step, state: $0.state == .running ? .cancelled : $0.state)
        }
    }

    func run(confirm: @escaping () async -> Bool) {
        guard enabled, !running else { return }
        running = true
        let identity = generation
        task = Task { [weak self] in
            guard let self else { return }
            let accepted = await confirm()
            guard !Task.isCancelled, enabled, generation == identity else { return }
            defer { running = false; task = nil }
            guard accepted, let stream = service.run() else { return }
            progress = []
            for await event in stream {
                guard !Task.isCancelled, enabled, generation == identity else { return }
                progress.removeAll { $0.step == event.step }
                progress.append(event)
            }
        }
    }
}
