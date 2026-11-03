import Foundation
import Observation

@MainActor @Observable
final class DownloadQueue {
    private(set) var jobs: [DownloadJob] {
        get {
            let now = clock()
            if now >= nextExpiryCheck {
                nextExpiryCheck = now.addingTimeInterval(60)
                let count = storedJobs.count
                expire(now: now)
                if storedJobs.count != count { save() }
            }
            return storedJobs
        }
        set { storedJobs = newValue }
    }
    private var storedJobs: [DownloadJob] = []
    @ObservationIgnored private var nextExpiryCheck = Date.distantPast
    private(set) var persistenceError: String?
    let maxConcurrent: Int
    var destination: URL

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let tools: DownloadToolLookup
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var runners: [String: any DownloadRunner] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var operations: [String: UUID] = [:]
    @ObservationIgnored private var persistence: Task<Void, Error>?
    @ObservationIgnored private var stopped = false

    init(
        file: URL? = AppPaths.applicationSupport().appending(path: "Notchcast/downloads.json"),
        destination: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads"),
        maxConcurrent: Int = 3, tools: DownloadToolLookup = DownloadToolLookup(),
        clock: @escaping () -> Date = { Date() }
    ) async throws {
        self.file = file
        self.destination = destination
        self.maxConcurrent = max(1, maxConcurrent)
        self.tools = tools
        self.clock = clock
        let loaded = try await Self.load(file: file, now: clock())
        storedJobs = loaded.jobs
        save()
        try await flush()
        persistenceError = loaded.error
    }

    isolated deinit {
        for task in tasks.values { task.cancel() }
    }

    func register(_ runner: any DownloadRunner) {
        runners[runner.kind] = runner
        pump()
    }

    @discardableResult
    func enqueue(
        kind: String, sources: [String], options: [String: String] = [:], group: String? = nil
    ) -> [DownloadJob] {
        let now = clock()
        expire(now: now)
        let available = runners[kind] != nil
        let added = sources.map {
            var job = DownloadJob(id: UUID().uuidString, kind: kind, source: $0, title: $0,
                                  group: group, created: now, options: options)
            if !available {
                job.state = .failed
                job.finished = now
                job.detail = String(localized: "This download type is not available.")
            }
            return job
        }
        storedJobs.append(contentsOf: added)
        save()
        pump()
        return added
    }

    func cancel(_ id: String) {
        guard let index = storedJobs.firstIndex(where: { $0.id == id }), !storedJobs[index].state.isFinished else { return }
        tasks[id]?.cancel()
        storedJobs[index].state = .cancelled
        storedJobs[index].finished = clock()
        save()
        pump()
    }

    func retry(_ id: String) {
        guard let index = storedJobs.firstIndex(where: { $0.id == id }), storedJobs[index].state.isFinished else { return }
        var job = storedJobs.remove(at: index)
        job.state = .waiting
        job.progress = nil
        job.output = nil
        job.detail = nil
        job.finished = nil
        storedJobs.append(job)
        save()
        pump()
    }

    func remove(_ id: String) {
        tasks[id]?.cancel()
        storedJobs.removeAll { $0.id == id }
        save()
        pump()
    }

    func clearFinished() {
        storedJobs.removeAll { $0.state.isFinished }
        save()
    }

    func stop() async {
        stopped = true
        let running = Array(tasks.values)
        for task in running { task.cancel() }
        for index in storedJobs.indices where storedJobs[index].state == .running {
            storedJobs[index].state = .interrupted
            storedJobs[index].finished = clock()
        }
        save()
        for task in running { await task.value }
        do {
            try await flush()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func flush() async throws {
        try await persistence?.value
    }

    private func pump() {
        guard !stopped else { return }
        while tasks.count < maxConcurrent,
              let job = storedJobs.first(where: {
                  $0.state == .waiting && tasks[$0.id] == nil && runners[$0.kind] != nil
              }),
              let runner = runners[job.kind] {
            begin(job, runner: runner)
        }
    }

    private func begin(_ job: DownloadJob, runner: any DownloadRunner) {
        guard let index = storedJobs.firstIndex(where: { $0.id == job.id }) else { return }
        storedJobs[index].state = .running
        let operation = UUID()
        operations[job.id] = operation
        let context = DownloadRunContext(destination: destination, tools: tools, report: { [weak self] progress in
            guard let self, operations[job.id] == operation,
                  let index = storedJobs.firstIndex(where: { $0.id == job.id }),
                  storedJobs[index].state == .running else { return }
            var progress = progress
            if let fraction = progress.fraction { progress.fraction = fraction.isFinite ? min(1, max(0, fraction)) : nil }
            storedJobs[index].progress = progress
        }, detail: { [weak self] detail in
            guard let self, operations[job.id] == operation,
                  let index = storedJobs.firstIndex(where: { $0.id == job.id }),
                  storedJobs[index].state == .running else { return }
            storedJobs[index].detail = detail
        })
        let runningJob = storedJobs[index]
        tasks[job.id] = Task { [weak self, tools] in
            let result: Result<URL?, Error>
            do {
                try Task.checkCancellation()
                try await Self.checkTools(runner.tools, lookup: tools)
                let output = try await runner.run(runningJob, context: context)
                try Task.checkCancellation()
                result = .success(output)
            } catch {
                result = .failure(error)
            }
            self?.complete(job.id, operation: operation, result: result)
        }
        save()
    }

    private func complete(_ id: String, operation: UUID, result: Result<URL?, Error>) {
        guard operations[id] == operation else { return }
        tasks[id] = nil
        operations[id] = nil
        if let index = storedJobs.firstIndex(where: { $0.id == id }), storedJobs[index].state == .running {
            storedJobs[index].finished = clock()
            switch result {
            case .success(let output):
                storedJobs[index].state = .done
                storedJobs[index].output = output?.path
            case .failure(let error):
                storedJobs[index].state = error is CancellationError ? .cancelled : .failed
                storedJobs[index].detail = error is CancellationError ? nil : error.localizedDescription
            }
            save()
        }
        pump()
    }

    @concurrent
    private static func checkTools(_ required: [DownloadTool], lookup: DownloadToolLookup) async throws {
        for tool in required {
            try Task.checkCancellation()
            if lookup.find(tool) == nil { throw MissingTool(tool: tool) }
        }
    }

    private struct MissingTool: LocalizedError {
        let tool: DownloadTool
        var errorDescription: String? { tool.missingDetail }
    }

    private func expire(now: Date) {
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        storedJobs.removeAll { $0.state.isFinished && ($0.finished ?? $0.created) <= cutoff }
    }

    private func save() {
        guard let file else { return }
        let snapshot = storedJobs
        let previous = persistence
        persistence = Task { [weak self] in
            _ = try? await previous?.value
            do {
                try await Self.write(snapshot, file: file)
                self?.persistenceError = nil
            } catch {
                self?.persistenceError = error.localizedDescription
                throw error
            }
        }
    }

    @concurrent
    private static func load(file: URL?, now: Date) async throws -> (jobs: [DownloadJob], error: String?) {
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return ([], nil) }
        let data = try Data(contentsOf: file)
        var jobs: [DownloadJob]
        do {
            jobs = try JSONDecoder().decode([DownloadJob].self, from: data)
        } catch {
            let badFile = file.appendingPathExtension("bad")
            if FileManager.default.fileExists(atPath: badFile.path) {
                try FileManager.default.moveItem(at: badFile, to: badFile.appendingPathExtension(UUID().uuidString))
            }
            try FileManager.default.moveItem(at: file, to: badFile)
            return ([], error.localizedDescription)
        }
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        jobs.removeAll { $0.state.isFinished && ($0.finished ?? $0.created) <= cutoff }
        for index in jobs.indices where jobs[index].state == .running {
            jobs[index].state = .interrupted
            jobs[index].finished = now
        }
        return (jobs, nil)
    }

    @concurrent
    private static func write(_ jobs: [DownloadJob], file: URL) async throws {
        let data = try JSONEncoder().encode(jobs)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
