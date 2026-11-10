import Foundation
import Observation

@MainActor
@Observable
final class DistillModule: NotchcastModule {
    var commandTask: Task<Void, Never>?
    let state: DownloadsQueueController
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let services: NotchcastDownloadServices
    @ObservationIgnored private var operation: UUID?

    var activity: DownloadsActivity { DownloadsActivity(jobs: state.queue?.jobs ?? []) }

    init(preferences: NotchcastPreferences, services: NotchcastDownloadServices,
         file: URL, destination: URL, report: @escaping (String) -> Void) {
        self.preferences = preferences
        self.services = services
        state = DownloadsQueueController(
            file: file, destination: destination, maxConcurrent: 1,
            speechKinds: [DistillRunner.kind, DistillConvertRunner.kind], tools: services.tools,
            releaseSpeech: services.releaseSpeech, report: report)
    }

    func start() {
        guard operation == nil else { return }
        let id = UUID()
        operation = id
        state.start { [weak self] queue in
            guard let self, operation == id else { return }
            queue.register(services.distillRunner(timestamps: { [preferences] in preferences.isOn(.distillTimestamps) }))
            trackConvert(id, queue: queue)
        }
    }

    func stop() {
        commandTask?.cancel()
        commandTask = nil
        operation = nil
        state.stop()
    }

    /// Holds each new link until `run`; one already held, waiting or running is not added again.
    func add(text: String) {
        guard let queue = state.queue else { return }
        var keys = Set(queue.jobs.filter { $0.kind == DistillRunner.kind && !$0.state.isFinished }
            .map { LinkCleaner.key($0.source) })
        let links = LinkCleaner.links(in: text).filter { keys.insert(LinkCleaner.key($0)).inserted }
        queue.enqueue(kind: DistillRunner.kind, sources: links, held: true)
    }

    func run() {
        state.queue?.release(DistillRunner.kind)
    }

    func convert() {
        guard preferences.isOn(.distillConvert), let queue = state.queue else { return }
        queue.enqueue(kind: DistillConvertRunner.kind, sources: [state.destination.path])
    }

    private func trackConvert(_ id: UUID, queue: DownloadQueue) {
        guard operation == id else { return }
        let enabled = withObservationTracking { preferences.isOn(.distillConvert) } onChange: { [weak self, weak queue] in
            Task { @MainActor [weak self, weak queue] in
                guard let queue else { return }
                self?.trackConvert(id, queue: queue)
            }
        }
        if enabled { queue.register(services.convertRunner) } else { queue.unregister(DistillConvertRunner.kind) }
    }
}
