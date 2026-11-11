import Foundation
import Observation

@MainActor
protocol FleetTransport: Sendable {
    func read() async throws -> FleetSnapshot
}

@MainActor
@Observable
final class FleetPanelModule: NotchcastModule {
    private(set) var local = FleetSnapshot.Column.sourceOff
    private(set) var remote = FleetSnapshot.Column.linkDown
    private let readLocal: @MainActor () async -> FleetSnapshot
    @ObservationIgnored var transport: (any FleetTransport)?
    private let now: () -> Date
    private let availabilityChanged: () -> Void
    private var enabled = false
    private var operation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(readLocal: @escaping @MainActor () async -> FleetSnapshot = FleetLocalSource.read,
         transport: (any FleetTransport)? = nil, now: @escaping () -> Date = Date.init,
         availabilityChanged: @escaping () -> Void = {}) {
        self.readLocal = readLocal
        self.transport = transport
        self.now = now
        self.availabilityChanged = availabilityChanged
    }

    func start() { enabled = true; refresh(); availabilityChanged() }
    func stop() {
        enabled = false
        operation = UUID()
        task?.cancel()
        task = nil
        local = .sourceOff
        remote = .linkDown
        availabilityChanged()
    }

    func refresh(completion: (@MainActor () -> Void)? = nil) {
        guard enabled else { return }
        task?.cancel()
        operation = UUID()
        let identity = operation
        let timestamp = now()
        task = Task { [weak self, readLocal, transport] in
            async let localValue = readLocal()
            async let remoteValue = Self.remoteColumn(transport, now: timestamp)
            let (snapshot, remote) = await (localValue, remoteValue)
            guard let self, self.enabled, self.operation == identity, !Task.isCancelled else { return }
            self.local = snapshot.column(now: self.now(), remote: false)
            self.remote = remote
            completion?()
        }
    }

    func waitUntilIdle() async { await task?.value }

    private static func remoteColumn(_ transport: (any FleetTransport)?, now: Date) async -> FleetSnapshot.Column {
        guard let transport else { return .linkDown }
        do {
            return try await transport.read().column(now: now, remote: true)
        } catch MachLinkMessage.Failure.disconnected {
            return .linkDown
        } catch {
            return .failed
        }
    }

    var message: String {
        Self.localMessage(local) + " " + Self.remoteMessage(remote)
    }

    static func localMessage(_ column: FleetSnapshot.Column) -> String {
        switch column {
        case .rows: String(localized: "This Mac: \(column.waiting) waiting, \(column.working) working.", table: "Notchcast")
        case .sourceOff, .remoteOff: String(localized: "This Mac: Agent Threads is off.", table: "Notchcast")
        case .linkDown, .failed: String(localized: "This Mac: could not read threads.", table: "Notchcast")
        }
    }

    static func remoteMessage(_ column: FleetSnapshot.Column) -> String {
        switch column {
        case .rows: String(localized: "Other Mac: \(column.waiting) waiting, \(column.working) working.", table: "Notchcast")
        case .sourceOff, .remoteOff: String(localized: "Other Mac: remote feature is off.", table: "Notchcast")
        case .linkDown: String(localized: "Other Mac: link is down.", table: "Notchcast")
        case .failed: String(localized: "Other Mac: could not read threads.", table: "Notchcast")
        }
    }

    nonisolated static let command = NotchcastCommand(
        slug: "show-fleet", name: String(localized: "Show Fleet", table: "Notchcast"),
        sfSymbol: "desktopcomputer", feature: .fleetPanel,
        isEnabled: { NotchcastPreferences.shared.isOn(.fleetPanel) },
        run: { FleetPanelModule.shared.refresh {
            NotchcastHost.current.showMessage(FleetPanelModule.shared.message, .neutral)
        } })
}
