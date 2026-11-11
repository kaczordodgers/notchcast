import Foundation

@MainActor
final class ConvertFilesModule: NotchcastModule {
    private(set) var enabled = false
    private var queue: DownloadQueue?

    func start() { enabled = true }
    func stop() {
        enabled = false
        guard let queue else { return }
        for job in queue.jobs where job.kind == ConvertFilesRunner.kind && !job.state.isFinished {
            queue.cancel(job.id)
        }
    }

    func attach(to queue: DownloadQueue, post: @escaping @MainActor @Sendable (String) -> Void) {
        self.queue = queue
        queue.register(ConvertFilesRunner(post: post))
    }

    @discardableResult
    func convert(_ sources: [URL], target: String, pages: String = "") throws -> [DownloadJob] {
        guard enabled, let queue, let first = sources.first else {
            throw ConvertFilesPlan.Failure(message: String(localized: "Convert Files is unavailable.", table: "Notchcast"))
        }
        let options = ConvertFilesRunner.Options(sources: sources.map(\.path), target: target, pages: pages)
        return queue.enqueue(kind: ConvertFilesRunner.kind, sources: [first.path], options: try DownloadJob.encode(options))
    }
}
