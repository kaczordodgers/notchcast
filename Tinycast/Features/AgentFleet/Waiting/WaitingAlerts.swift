import Foundation
import Observation

@MainActor
@Observable
final class WaitingAlerts {
    private(set) var count = 0
    private(set) var failure: String?
    @ObservationIgnored private let source: any WaitingThreadSource
    @ObservationIgnored private let watcher: any WaitingFolderWatching
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let post: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var running = false
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var baseline = true
    @ObservationIgnored private var previous: Set<Key> = []

    private struct Key: Hashable {
        let id: String
        let kind: WaitingThread.Kind
    }

    init(source: any WaitingThreadSource, watcher: any WaitingFolderWatching,
         folder: URL, post: @escaping @MainActor (String) -> Void) {
        self.source = source
        self.watcher = watcher
        self.folder = folder
        self.post = post
    }

    func start() {
        guard !running, !folder.pathComponents.contains("agent-2784f2ac") else { return }
        running = true
        baseline = true
        let generation = generation
        do {
            try watcher.start(folder: folder) { [weak self] in
                guard let self, self.generation == generation else { return }
                self.changed()
            }
            changed()
        } catch {
            failure = error.localizedDescription
            stop()
        }
    }

    func stop() {
        running = false
        generation += 1
        watcher.stop()
        task?.cancel()
        task = nil
        pending = 0
        previous = []
        count = 0
    }

    func settle() async { await task?.value }

    private func changed() {
        guard running else { return }
        pending += 1
        guard task == nil else { return }
        let generation = generation
        task = Task { [weak self, source, folder] in
            while let self, self.pending > 0 {
                self.pending -= 1
                do {
                    let threads = try await source.readWaitingThreads(in: folder)
                    guard !Task.isCancelled, self.generation == generation else { return }
                    self.apply(threads)
                    self.failure = nil
                } catch {
                    guard !Task.isCancelled, self.generation == generation else { return }
                    if self.failure != error.localizedDescription { self.post(error.localizedDescription) }
                    self.failure = error.localizedDescription
                    self.count = 0
                    self.previous = []
                    self.baseline = true
                }
            }
            guard let self, self.generation == generation else { return }
            self.task = nil
        }
    }

    private func apply(_ threads: [WaitingThread]) {
        var current: Set<Key> = []
        for thread in threads {
            let key = Key(id: thread.id, kind: thread.kind)
            if current.insert(key).inserted, !baseline, !previous.contains(key) { post(thread.title) }
        }
        previous = current
        baseline = false
        count = current.count
    }
}
