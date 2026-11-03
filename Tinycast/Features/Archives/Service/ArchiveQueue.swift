import Foundation
import Observation

@Observable @MainActor
final class ArchiveQueue {
    private(set) var jobs: [ArchiveJob] = []
    @ObservationIgnored private let runner: ArchiveExtractionRunner
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var activeID: UUID?

    init(runner: ArchiveExtractionRunner = ArchiveExtractionRunner()) { self.runner = runner }

    isolated deinit { worker?.cancel() }

    @discardableResult
    func enqueue(_ archive: URL) -> UUID {
        let id = UUID()
        jobs.append(ArchiveJob(id: id, archive: archive.standardizedFileURL))
        startNext()
        return id
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if activeID == id {
            jobs[index].state = .cancelling
            worker?.cancel()
        } else if jobs[index].state == .queued {
            jobs[index].state = .cancelled
        }
    }

    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              [.failed, .cancelled].contains(jobs[index].state), activeID != id else { return }
        jobs[index].state = .queued
        jobs[index].failure = nil
        jobs[index].bytesWritten = 0
        startNext()
    }

    func stop() {
        for job in jobs where job.state == .queued || job.id == activeID { cancel(job.id) }
    }

    private func startNext() {
        guard activeID == nil, let index = jobs.firstIndex(where: { $0.state == .queued }) else { return }
        let job = jobs[index]
        activeID = job.id
        jobs[index].state = .preflighting
        worker = Task { [weak self, runner] in
            do {
                let output = try await runner.extract(job.archive) { [weak self] progress in
                    guard let self, self.activeID == job.id, !Task.isCancelled,
                          let index = self.jobs.firstIndex(where: { $0.id == job.id }),
                          self.jobs[index].state != .cancelling else { return }
                    self.jobs[index].state = .extracting
                    self.jobs[index].totalBytes = progress.totalBytes
                    self.jobs[index].bytesWritten = progress.bytesWritten
                }
                self?.finish(job.id, output: output, failure: nil, cancelled: false)
            } catch is CancellationError {
                self?.finish(job.id, output: nil, failure: nil, cancelled: true)
            } catch {
                let failure = (error as? ArchiveFailure) ?? .filesystem(String(describing: error))
                self?.finish(job.id, output: nil, failure: failure, cancelled: false)
            }
        }
    }

    private func finish(_ id: UUID, output: URL?, failure: ArchiveFailure?, cancelled: Bool) {
        guard activeID == id, let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].output = output
        jobs[index].failure = failure
        jobs[index].state = cancelled ? .cancelled : failure == nil ? .finished : .failed
        if output != nil { jobs[index].bytesWritten = jobs[index].totalBytes }
        activeID = nil
        worker = nil
        startNext()
    }
}
