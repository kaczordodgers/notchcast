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
    private let settings: AgentFleetSettings
    private let preferences: NotchcastPreferences
    private var running = false
    private var refresh: Task<Void, Never>?

    init(threads: T3ThreadsModule, fleet: FleetModule, island: AgentIslandModule, bots: BotHostModule,
         preferences: NotchcastPreferences, settings: AgentFleetSettings, post: @escaping @MainActor (String) -> Void) {
        source = T3Threads(threads)
        watcher = Watcher()
        alerts = WaitingAlerts(source: source, watcher: watcher,
            folder: URL(filePath: "/synthetic-snapshots"), post: post)
        self.fleet = fleet
        self.island = island
        self.bots = bots
        self.preferences = preferences
        self.settings = settings
        fleet.configure(source: source, destinations: settings.destinations, clock: Date.init)
        island.sources = [source, bots]
    }

    func start() { running = true; observe() }
    func stop() { running = false; refresh?.cancel(); alerts.stop() }

    private func observe() {
        guard running else { return }
        let inputs = withObservationTracking {
            let waiting = preferences.isOn(.waitingAlerts)
            let fleetEnabled = preferences.isOn(.fleetPanel)
            let islandEnabled = preferences.isOn(.agentIsland) && preferences.isOn(.island)
            let destinations = settings.destinations
            _ = source.module.threads
            _ = source.module.isRunning
            _ = source.module.error
            _ = source.module.hasSnapshot
            _ = fleet.isEnabled
            _ = island.isRunning
            _ = bots.snapshot
            return (waiting: waiting, fleet: fleetEnabled, island: islandEnabled, destinations: destinations)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        if fleet.model?.destinations != inputs.destinations { fleet.model?.destinations = inputs.destinations }
        source.module.setDemand(inputs.waiting || inputs.fleet || inputs.island, for: "fleet")
        let polling = source.module.isRunning && !source.module.hasSnapshot && source.module.error == nil
        if inputs.waiting && !polling { alerts.start(); watcher.changed?() } else { alerts.stop() }
        refresh?.cancel()
        if inputs.fleet { refresh = Task { [fleet] in await fleet.refresh() } }
        if inputs.island { island.refresh(now: Date.timeIntervalSinceReferenceDate, pointerInside: false) }
    }
}
