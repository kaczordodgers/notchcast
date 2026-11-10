import Foundation
import Observation

@MainActor
@Observable
final class DownloadsQueueController {
    private(set) var queue: DownloadQueue?
    private(set) var failure: String?
    let destination: URL
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let maxConcurrent: Int
    @ObservationIgnored private let speechKinds: Set<String>
    @ObservationIgnored private let tools: DownloadToolLookup
    @ObservationIgnored private let report: (String) -> Void
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private let releaseSpeech: @MainActor @Sendable () async -> Void
    @ObservationIgnored private var speechPending = false

    /// `speechKinds` are the job kinds that hold the speech worker until none of them is due.
    init(file: URL, destination: URL, maxConcurrent: Int = 3, speechKinds: Set<String>,
         tools: DownloadToolLookup, releaseSpeech: @escaping @MainActor @Sendable () async -> Void = {},
         report: @escaping (String) -> Void) {
        self.file = file
        self.destination = destination
        self.maxConcurrent = maxConcurrent
        self.speechKinds = speechKinds
        self.tools = tools
        self.report = report
        self.releaseSpeech = releaseSpeech
    }

    isolated deinit { transition?.cancel() }

    func start(configure: @escaping @MainActor (DownloadQueue) throws -> Void) {
        guard operation == nil else { return }
        let id = UUID()
        operation = id
        failure = nil
        let previous = transition
        transition = Task { [weak self] in
            await previous?.value
            guard let self, operation == id, !Task.isCancelled else { return }
            do {
                let loaded = try await DownloadQueue(
                    file: file, destination: destination, maxConcurrent: maxConcurrent, tools: tools)
                guard operation == id, !Task.isCancelled else { await loaded.stop(); return }
                do {
                    try configure(loaded)
                } catch {
                    await loaded.stop()
                    throw error
                }
                queue = loaded
                trackSpeech(id, queue: loaded)
                if let problem = loaded.persistenceError { report(problem) }
            } catch {
                guard operation == id, !Task.isCancelled else { return }
                failure = error.localizedDescription
                report(error.localizedDescription)
            }
        }
    }

    func stop() {
        operation = nil
        transition?.cancel()
        let previous = transition
        let stopped = queue
        let release = releaseSpeech
        speechPending = false
        queue = nil
        transition = Task {
            await previous?.value
            await stopped?.stop()
            await release()
        }
    }

    private func trackSpeech(_ id: UUID, queue: DownloadQueue) {
        guard operation == id else { return }
        let pending = withObservationTracking { speechIsDue(queue) } onChange: { [weak self, weak queue] in
            Task { @MainActor [weak self, weak queue] in
                guard let queue else { return }
                self?.trackSpeech(id, queue: queue)
            }
        }
        let becameIdle = speechPending && !pending
        speechPending = pending
        if becameIdle {
            Task { [weak self, weak queue] in
                guard let self, let queue, operation == id, !speechIsDue(queue) else { return }
                await releaseSpeech()
            }
        }
    }

    private func speechIsDue(_ queue: DownloadQueue) -> Bool {
        queue.jobs.contains { speechKinds.contains($0.kind) && $0.state.isDue }
    }

    func settle() async { await transition?.value }
}
