import Foundation
import Observation

@MainActor
@Observable
final class DistillModule: NotchcastModule {
    var commandTask: Task<Void, Never>?
    let state: DownloadsQueueController
    private(set) var links: DistillQueue?
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let services: NotchcastDownloadServices
    @ObservationIgnored private let linksFile: URL
    @ObservationIgnored private var operation: UUID?

    var activity: DownloadsActivity { DownloadsActivity(jobs: state.queue?.jobs ?? []) }

    init(preferences: NotchcastPreferences, services: NotchcastDownloadServices,
         file: URL, linksFile: URL, destination: URL, report: @escaping (String) -> Void) {
        self.preferences = preferences
        self.services = services
        self.linksFile = linksFile
        state = DownloadsQueueController(
            file: file, destination: destination, maxConcurrent: 1, tools: services.tools,
            releaseSpeech: services.releaseSpeech, report: report)
    }

    func start() {
        guard operation == nil else { return }
        let id = UUID()
        operation = id
        state.start { [weak self] queue in
            guard let self, operation == id else { return }
            links = try DistillQueue(file: linksFile)
            queue.register(NotchcastDownloadRunner(services.distillRunner, tools: []) { [preferences] in
                ["timestamps": preferences.isOn(.distillTimestamps) ? "true" : "false"]
            })
            trackConvert(id, queue: queue)
        }
    }

    func stop() {
        commandTask?.cancel()
        commandTask = nil
        operation = nil
        links = nil
        state.stop()
    }

    func run() async throws {
        guard let links, let queue = state.queue else { return }
        let id = operation
        let pending = links.links.filter { $0.state == .waiting }
        let transferred = Set(queue.jobs.filter { $0.kind == "distill" }.compactMap { $0.options["distillLinkID"] })
        for link in pending where !transferred.contains(link.id.uuidString) {
            queue.enqueue(kind: "distill", sources: [link.url], options: ["distillLinkID": link.id.uuidString])
        }
        try await queue.flush()
        try Task.checkCancellation()
        guard operation == id, state.queue === queue else { return }
        for link in pending { try links.remove(link.id) }
    }

    func convert() {
        guard preferences.isOn(.distillConvert), let queue = state.queue else { return }
        queue.enqueue(kind: "convert", sources: [state.destination.path])
    }

    private func trackConvert(_ id: UUID, queue: DownloadQueue) {
        guard operation == id else { return }
        let enabled = withObservationTracking { preferences.isOn(.distillConvert) } onChange: { [weak self, weak queue] in
            Task { @MainActor [weak self, weak queue] in
                guard let queue else { return }
                self?.trackConvert(id, queue: queue)
            }
        }
        if enabled { queue.register(services.convertRunner) } else { queue.unregister("convert") }
    }
}
