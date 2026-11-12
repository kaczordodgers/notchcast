import Foundation
import Observation

@MainActor @Observable
final class AIUsageModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var snapshots: [AIUsageSnapshot] = []
    private(set) var gatewayDown = false
    private(set) var isLoading = false
    private(set) var refreshedAt: Date?
    let otherMac: OtherMacUsageService
    @ObservationIgnored private let source: AIUsageSnapshotAdapter
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var lastGateway: String?

    var needsRefresh: Bool {
        guard lastGateway == preferences.aiUsageGateway, let refreshedAt else { return true }
        let now = clock()
        return now.timeIntervalSince(refreshedAt) > 60 || snapshots.contains { snapshot in
            snapshot.windows.contains { window in
                window.resetsAt.map { refreshedAt < $0 && $0 <= now } ?? false
            }
        }
    }

    var peerStatus: String {
        otherMac.peerStatus == .available ? String(localized: "Connected", table: "Notchcast") : String(localized: "Not connected", table: "Notchcast")
    }

    init(
        preferences: NotchcastPreferences = .shared,
        channel: MachLinkChannel = MachLinkChannel(),
        clock: @escaping () -> Date = { Date.now }
    ) {
        self.preferences = preferences
        self.clock = clock
        let source = AIUsageSnapshotAdapter()
        self.source = source
        otherMac = OtherMacUsageService(source: source, channel: channel, clock: { Date() })
        channel.registerUsageRoute(source: source, preferences: preferences)
    }

    func start() {
        guard !isRunning else { return }
        generation += 1
        isRunning = true
        trackPeerPolicy(generation: generation)
    }

    func stop() {
        isRunning = false
        generation += 1
        snapshots = []
        refreshedAt = nil
        gatewayDown = false
        isLoading = false
        source.snapshots = []
        otherMac.configure(peerEnabled: false, providers: [])
    }

    func refresh() async throws {
        guard isRunning else { return }
        let request = UUID()
        refreshID = request
        isLoading = true
        defer { if refreshID == request { isLoading = false } }
        let operation = generation
        let gateway = preferences.aiUsageGateway
        do {
            let values = try await AIUsageProvider.fetch(gateway: gateway, now: clock())
            try Task.checkCancellation()
            guard isRunning, generation == operation, refreshID == request,
                  preferences.aiUsageGateway == gateway else { return }
            snapshots = values
            source.snapshots = values
            gatewayDown = false
            refreshedAt = clock()
            lastGateway = gateway
        } catch {
            try Task.checkCancellation()
            guard isRunning, generation == operation, refreshID == request,
                  preferences.aiUsageGateway == gateway else { return }
            gatewayDown = true
            refreshedAt = nil
            snapshots = []
            source.snapshots = []
        }
    }

    private func trackPeerPolicy(generation operation: Int) {
        guard isRunning, generation == operation else { return }
        withObservationTracking {
            configurePeer()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackPeerPolicy(generation: operation) }
        }
    }

    private func configurePeer() {
        otherMac.configure(
            peerEnabled: preferences.isEnabled(.aiUsageOtherMac),
            providers: Set(snapshots.map(\.providerID).filter { !$0.isEmpty }))
    }
}
