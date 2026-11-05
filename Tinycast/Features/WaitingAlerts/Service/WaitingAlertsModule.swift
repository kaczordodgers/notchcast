import Foundation
import Observation

@MainActor
@Observable
final class WaitingAlertsModule: NotchcastModule {
    private(set) var waiting: [WaitingAlert] = []
    private(set) var waitingCount = 0
    private let watcher: any WaitingAlertsWatching
    private let path: String
    private let read: @MainActor () async throws -> [AgentThread]
    private let post: @MainActor (String) -> Void
    private let now: @MainActor () -> TimeInterval
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private let availabilityChanged: @MainActor () -> Void
    private var previous: [WaitingAlert]?
    private var enabled = false
    private var watching = false
    private var generation = UUID()
    private var lastRefresh: TimeInterval?
    private var dirty = false
    private var report = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(watcher: any WaitingAlertsWatching = WaitingAlertsWatcher(),
         path: String = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".t3/userdata").path,
         read: @escaping @MainActor () async throws -> [AgentThread] = {
             let state = NotchcastCore.agentThreads.state
             await state.waitUntilIdle()
             try Task.checkCancellation()
             state.refresh()
             await state.waitUntilIdle()
             try Task.checkCancellation()
             guard state.status == .ready else { throw WaitingAlertsFailure.refresh }
             return state.threads
         },
         post: @escaping @MainActor (String) -> Void = { AppCore.shared.showMessage($0, tone: .neutral) },
         now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds($0))
         },
         availabilityChanged: @escaping @MainActor () -> Void = {}) {
        self.watcher = watcher
        self.path = path
        self.read = read
        self.post = post
        self.now = now
        self.sleep = sleep
        self.availabilityChanged = availabilityChanged
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        let identity = generation
        watching = watcher.start(path: path) { [weak self] in
            guard let self, self.generation == identity else { return }
            self.refresh()
        }
        if watching { refresh() }
        availabilityChanged()
    }

    func stop() {
        enabled = false
        generation = UUID()
        watcher.stop()
        task?.cancel()
        task = nil
        previous = nil
        waiting = []
        waitingCount = 0
        lastRefresh = nil
        dirty = false
        report = false
        availabilityChanged()
    }

    func refresh(report: Bool = false) {
        guard enabled else { return }
        guard watching else {
            if report { post(String(localized: "T3 data folder is unavailable.")) }
            return
        }
        self.report = self.report || report
        dirty = true
        guard task == nil else { return }
        let identity = generation
        task = Task { [weak self] in
            guard let self else { return }
            while self.dirty {
                let delay = max(0, (self.lastRefresh ?? (self.now() - 10)) + 10 - self.now())
                do { if delay > 0 { try await self.sleep(delay) } } catch { return }
                guard !Task.isCancelled, self.enabled, self.generation == identity else { return }
                self.dirty = false
                self.lastRefresh = self.now()
                do {
                    let threads = try await self.read()
                    guard !Task.isCancelled, self.enabled, self.generation == identity else { return }
                    let current = WaitingAlertsEngine.waiting(in: threads)
                    let notices = WaitingAlertsEngine.notices(previous: self.previous, current: current)
                    self.previous = current
                    if self.waiting != current { self.waiting = current }
                    if self.waitingCount != current.count { self.waitingCount = current.count }
                    if self.report {
                        self.post(WaitingAlertsEngine.countMessage(current.count))
                    } else if let message = WaitingAlertsEngine.message(notices) { self.post(message) }
                } catch {
                    guard !Task.isCancelled, self.enabled, self.generation == identity else { return }
                    if self.report { self.post(String(localized: "Could not refresh agent threads.")) }
                }
                self.report = false
            }
            self.task = nil
        }
    }

    nonisolated static let command = NotchcastCommand(
        slug: "show-waiting-agents", name: String(localized: "Show Waiting Agents"),
        sfSymbol: "bubble.left", feature: .waitingAlerts,
        isEnabled: {
            NotchcastPreferences.shared.isOn(.agentThreads) && NotchcastPreferences.shared.isOn(.waitingAlerts)
        }, run: { NotchcastCore.waitingAlerts.refresh(report: true) })
}

enum WaitingAlertsFailure: Error { case refresh }
