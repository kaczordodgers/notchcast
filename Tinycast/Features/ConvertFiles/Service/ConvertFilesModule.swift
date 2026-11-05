import Foundation

@MainActor
final class ConvertFilesModule: NotchcastModule {
    private(set) var enabled = false
    private var queue: DownloadQueue?

    func start() { enabled = true }
    func stop() {
        enabled = false
        guard let queue else { return }
        for job in queue.jobs where job.kind == "convert-files" && !job.state.isFinished {
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
        guard let encoded = String(bytes: try JSONEncoder().encode(sources.map(\.path)), encoding: .utf8) else {
            throw ConvertFilesPlan.Failure(message: String(localized: "Invalid file paths.", table: "Notchcast"))
        }
        return queue.enqueue(kind: "convert-files", sources: [first.path],
                             options: ["sources": encoded, "target": target, "pages": pages])
    }
}
