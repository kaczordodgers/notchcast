import Foundation
import Observation

@MainActor
final class BackupStatusModule: NotchcastModule {
    typealias Cancel = @MainActor () -> Void
    typealias Watch = @MainActor (@escaping @MainActor () -> Void) -> Cancel
    typealias Schedule = @MainActor (Date, @escaping @MainActor () -> Void) -> Cancel

    private let read: @MainActor () async throws -> Data
    private let watch: Watch
    private let schedule: Schedule
    private let now: @MainActor () -> Date
    private let post: @MainActor (String) -> Void
    private let staleAfter: TimeInterval
    private let configurationNotice: @MainActor () -> String?
    private var cancelWatch: Cancel?
    private var cancelDeadline: Cancel?
    private var reading: Task<Void, Never>?
    private var generation = 0
    private var running = false
    private var enabled = false
    private var cancelRestart: Cancel?
    private var status: BackupStatus?
    private var previousIssues: [BackupStatusEngine.Issue] = []

    init(read: @escaping @MainActor () async throws -> Data, watch: @escaping Watch,
         schedule: @escaping Schedule, now: @escaping @MainActor () -> Date = { Date() },
         staleAfter: TimeInterval = 7200, configurationNotice: @escaping @MainActor () -> String? = { nil },
         post: @escaping @MainActor (String) -> Void) {
        self.read = read
        self.watch = watch
        self.schedule = schedule
        self.now = now
        self.staleAfter = staleAfter
        self.configurationNotice = configurationNotice
        self.post = post
        trackPath()
    }

    /// A settings restore writes the path without the settings row, so the module watches it itself.
    private func trackPath() {
        withObservationTracking { _ = configurationNotice() } onChange: { [weak self] in
            Task { @MainActor in
                self?.trackPath()
                self?.pathChanged()
            }
        }
    }

    func start() {
        guard !running else { return }
        enabled = true
        if let notice = configurationNotice() {
            post(notice)
            return
        }
        begin()
    }

    // The debounce keeps each keystroke from watching, and alerting on, a half-typed path.
    func pathChanged() {
        guard enabled else { return }
        cancelRestart?()
        cancelRestart = schedule(now().addingTimeInterval(1)) { [weak self] in
            guard let self else { return }
            self.cancelRestart = nil
            self.halt()
            if self.configurationNotice() == nil { self.begin() }
        }
    }

    func stop() {
        enabled = false
        cancelRestart?()
        cancelRestart = nil
        halt()
    }

    private func begin() {
        running = true
        cancelWatch = watch { [weak self] in self?.reload() }
        reload()
    }

    private func halt() {
        running = false
        generation += 1
        reading?.cancel()
        reading = nil
        cancelWatch?()
        cancelWatch = nil
        cancelDeadline?()
        cancelDeadline = nil
        status = nil
        previousIssues = []
    }

    private func reload() {
        guard running else { return }
        generation += 1
        let identity = generation
        reading?.cancel()
        reading = Task { [weak self, read] in
            let result: BackupStatus?
            do { result = try BackupStatusEngine.parse(await read()) } catch { result = nil }
            guard !Task.isCancelled, let self, self.running, self.generation == identity else { return }
            self.status = result
            self.evaluate()
        }
    }

    private func evaluate() {
        guard running else { return }
        cancelDeadline?()
        cancelDeadline = nil
        let date = now()
        let issues = BackupStatusEngine.issues(status, now: date, staleAfter: staleAfter)
        if issues.contains(where: { !previousIssues.contains($0) }) {
            post(String(localized: "Backup needs attention.", table: "Notchcast"))
        }
        previousIssues = issues
        guard let status else { return }
        let dates = [status.lastSuccess, status.lastAttempt, status.mbpTimeMachine?.latest]
            .compactMap { $0?.addingTimeInterval(staleAfter) }.filter { $0 > date }
        if let deadline = dates.min() {
            cancelDeadline = schedule(deadline) { [weak self] in self?.evaluate() }
        }
    }

    isolated deinit {
        cancelRestart?()
        reading?.cancel()
        cancelWatch?()
        cancelDeadline?()
    }
}
