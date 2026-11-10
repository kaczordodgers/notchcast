import Foundation
import Observation

@MainActor
@Observable
final class WaitingAlertsModule: NotchcastModule {
    private(set) var waitingCount = 0
    private(set) var unavailable = false
    private let watcher: any WaitingAlertsWatching
    private let path: String
    private let reader: any WaitingAlertsReading
    private let post: @MainActor (String) -> Void
    private let availabilityChanged: @MainActor () -> Void
    private var previous: [WaitingAlert]?
    private var enabled = false
    private var watching = false
    private var generation = UUID()
    private var dirty = false
    private var report = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(watcher: any WaitingAlertsWatching = WaitingAlertsWatcher(),
         path: String = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".t3/userdata").path,
         reader: any WaitingAlertsReading = WaitingAlertsReader(),
         post: @escaping @MainActor (String) -> Void = { NotchcastHost.current.showMessage($0, .neutral) },
         availabilityChanged: @escaping @MainActor () -> Void = {}) {
        self.watcher = watcher
        self.path = path
        self.reader = reader
        self.post = post
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
        unavailable = !watching
        if watching { refresh() }
        availabilityChanged()
    }

    func stop() {
        enabled = false
        generation = UUID()
        watcher.stop()
        task?.cancel()
        previous = nil
        waitingCount = 0
        unavailable = false
        dirty = false
        report = false
        availabilityChanged()
    }

    func refresh(report: Bool = false) {
        guard enabled else { return }
        guard watching else {
            if report { post(String(localized: "T3 data is unavailable.", table: "Notchcast")) }
            return
        }
        self.report = self.report || report
        dirty = true
        guard task == nil else { return }
        let identity = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
                if self.enabled && self.dirty { self.refresh() }
            }
            while self.dirty {
                guard !Task.isCancelled, self.enabled, self.generation == identity else { return }
                self.dirty = false
                let report = self.report
                self.report = false
                do {
                    let current = try await self.reader.read()
                    guard !Task.isCancelled, self.enabled, self.generation == identity else { return }
                    self.unavailable = false
                    let notices = WaitingAlertsEngine.notices(previous: self.previous, current: current)
                    self.previous = current
                    if self.waitingCount != current.count { self.waitingCount = current.count }
                    if report {
                        self.post(WaitingAlertsEngine.countMessage(current.count))
                    } else if let message = WaitingAlertsEngine.message(notices, total: current.count) { self.post(message) }
                } catch {
                    guard !Task.isCancelled, self.enabled, self.generation == identity else { return }
                    self.unavailable = true
                    if report { self.post(String(localized: "T3 data is unavailable.", table: "Notchcast")) }
                }
            }
        }
    }

    nonisolated static let command = NotchcastCommand(
        slug: "show-waiting-agents", name: String(localized: "Show Waiting Agents", table: "Notchcast"),
        sfSymbol: "bubble.left", feature: .waitingAlerts,
        isEnabled: {
            NotchcastPreferences.shared.isOn(.waitingAlerts)
        }, run: { WaitingAlertsModule.shared.refresh(report: true) })
}
