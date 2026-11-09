import Foundation
import Observation

/// What the island shows for one Downloads queue: pure, so a harness drives it with plain job lists.
struct DownloadsIslandPolicy: Equatable, Sendable {
    struct Shown: Equatable, Sendable {
        let title: String?
        let value: IslandValue
        let progress: Double?
    }

    private var batch: Set<String> = []
    private var failed: Set<String>

    /// Failures already in the queue when it loads were reported by an earlier run.
    init(loaded jobs: [DownloadJob]) {
        failed = Set(jobs.filter { $0.state == .failed }.map(\.id))
    }

    mutating func update(_ jobs: [DownloadJob]) -> (shown: Shown?, failures: [DownloadJob]) {
        let failures = jobs.filter { $0.state == .failed && !failed.contains($0.id) }
        failed = Set(jobs.filter { $0.state == .failed }.map(\.id))
        let pending = jobs.filter { !$0.state.isFinished }.map(\.id)
        guard !pending.isEmpty else {
            batch = []
            return (nil, failures)
        }
        batch.formUnion(pending)
        let inBatch = jobs.filter { batch.contains($0.id) }
        let current = DownloadsActivity(jobs: jobs)
        let done = inBatch.count { $0.state.isFinished }
        return (Shown(title: current.currentTitle, value: .count(done, of: inBatch.count),
                      progress: current.fraction), failures)
    }

    static func message(for job: DownloadJob) -> String {
        let title = job.title.count > 40 ? String(job.title.prefix(39)) + "…" : job.title
        guard let detail = job.detail, !detail.isEmpty else { return title }
        return "\(title): \(detail)"
    }
}

/// Mirrors a Downloads queue onto the island for as long as its controller lives.
@MainActor
final class DownloadsIslandBridge {
    private weak var controller: DownloadsQueueController?
    private let center: IslandActivityCenter
    private var queue: ObjectIdentifier?
    private var policy: DownloadsIslandPolicy?
    private var activity: UUID?

    private init(controller: DownloadsQueueController, center: IslandActivityCenter) {
        self.controller = controller
        self.center = center
    }

    static func track(_ controller: DownloadsQueueController, center: IslandActivityCenter = .shared) {
        DownloadsIslandBridge(controller: controller, center: center).observe()
    }

    /// The onChange closure owns the bridge, so it lives exactly as long as there is something to observe.
    private func observe() {
        guard let controller else { return finish() }
        let (queue, jobs) = withObservationTracking {
            (controller.queue, controller.queue?.jobs ?? [])
        } onChange: { [self] in
            Task { @MainActor in observe() }
        }
        apply(queue.map(ObjectIdentifier.init), jobs: jobs)
    }

    private func apply(_ id: ObjectIdentifier?, jobs: [DownloadJob]) {
        guard let id else {
            queue = nil
            policy = nil
            return finish()
        }
        if queue != id {
            queue = id
            policy = DownloadsIslandPolicy(loaded: jobs)
        }
        guard let result = policy?.update(jobs) else { return }
        for job in result.failures {
            center.showMessage(DownloadsIslandPolicy.message(for: job), tone: .danger, dwell: 5,
                               id: "downloads.failed." + job.id)
        }
        guard let shown = result.shown else { return finish() }
        let title = shown.title ?? String(localized: "Downloading", table: "Notchcast")
        if let activity {
            center.update(activity, title: title, progress: .some(shown.progress), value: .some(shown.value))
        } else {
            activity = center.begin(IslandActivity(kind: .transfer, title: title, progress: shown.progress,
                                                   value: shown.value))
        }
    }

    private func finish() {
        guard let activity else { return }
        center.finish(activity)
        self.activity = nil
    }
}
