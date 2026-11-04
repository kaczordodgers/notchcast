import Foundation
import Observation

@MainActor
final class AgentFleetWiring: NotchcastModule {
    final class Watcher: WaitingFolderWatching {
        var changed: (@MainActor @Sendable () -> Void)?
        func start(folder: URL, changed: @escaping @MainActor @Sendable () -> Void) throws {
            self.changed = changed
        }
        func stop() { changed = nil }
    }

    let source: T3Threads
    let alerts: WaitingAlerts
    private let watcher: Watcher
    private let fleet: FleetModule
    private let island: AgentIslandModule
    private let bots: BotHostModule
    private let preferences: NotchcastPreferences
    private var running = false
    private var refresh: Task<Void, Never>?

    init(threads: T3ThreadsModule, fleet: FleetModule, island: AgentIslandModule, bots: BotHostModule,
         preferences: NotchcastPreferences, post: @escaping @MainActor (String) -> Void) {
        source = T3Threads(threads)
        watcher = Watcher()
        alerts = WaitingAlerts(source: source, watcher: watcher,
            folder: URL(filePath: "/synthetic-snapshots"), post: post)
        self.fleet = fleet
        self.island = island
        self.bots = bots
        self.preferences = preferences
        fleet.configure(source: source, destinations: [
            .init(machine: "Local", environmentID: "", workspacePath: nil, route: .local),
            .init(machine: "Remote", environmentID: "", workspacePath: nil, route: .linked)
        ], clock: Date.init)
        island.sources = [source, bots]
    }

    func start() { running = true; observe() }
    func stop() { running = false; refresh?.cancel(); alerts.stop() }

    private func observe() {
        guard running else { return }
        withObservationTracking {
            let waiting = preferences.isOn(.waitingAlerts)
            let fleetEnabled = preferences.isOn(.fleetPanel)
            let islandEnabled = preferences.isOn(.agentIsland)
            source.module.setDemand(waiting || fleetEnabled || islandEnabled, for: "fleet")
            _ = source.module.threads
            _ = source.module.isRunning
            _ = source.module.error
            if waiting { alerts.start(); watcher.changed?() } else { alerts.stop() }
            refresh?.cancel()
            if fleetEnabled { refresh = Task { [fleet] in await fleet.refresh() } }
            if islandEnabled { island.refresh(now: Date.timeIntervalSinceReferenceDate, pointerInside: false) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}
