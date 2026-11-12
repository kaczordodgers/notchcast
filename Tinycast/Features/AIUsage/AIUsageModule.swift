import Foundation
import Observation

@MainActor @Observable
final class AIUsageModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var snapshots: [AIUsageSnapshot] = []
    private(set) var gatewayDown = false
    private(set) var refreshedAt: Date?
    let otherMac: OtherMacUsageService
    @ObservationIgnored private let provider: AIUsageProvider?
    @ObservationIgnored private let source: AIUsageSnapshotAdapter
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var lastGateway: String?

    var needsRefresh: Bool {
        lastGateway != preferences.aiUsageGateway || (refreshedAt.map { Date.now.timeIntervalSince($0) > 60 } ?? true)
    }

    var peerStatus: String {
        otherMac.peerStatus == .available ? String(localized: "Connected", table: "Notchcast") : String(localized: "Not connected", table: "Notchcast")
    }

    init(
        provider: AIUsageProvider? = nil,
        preferences: NotchcastPreferences = .shared,
        channel: MachLinkChannel = MachLinkChannel()
    ) {
        self.provider = provider
        self.preferences = preferences
        let source = AIUsageSnapshotAdapter()
        self.source = source
        otherMac = OtherMacUsageService(source: source, channel: channel, clock: { Date() })
        channel.registerUsageRoute(provider: provider, preferences: preferences)
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
        source.snapshots = []
        otherMac.configure(peerEnabled: false, providers: [])
    }

    func refresh() async throws {
        guard isRunning else { return }
        let request = UUID()
        refreshID = request
        let operation = generation
        let gateway = preferences.aiUsageGateway
        do {
            let values: [AIUsageSnapshot]
            if let provider {
                values = await provider.refresh()
            } else {
                values = try await AIUsageProvider.fetch(gateway: gateway, now: .now)
            }
            try Task.checkCancellation()
            guard isRunning, generation == operation, refreshID == request,
                  preferences.aiUsageGateway == gateway else { return }
            snapshots = values
            source.snapshots = values
            gatewayDown = false
            refreshedAt = .now
            lastGateway = gateway
            configurePeer()
            try await otherMac.refresh()
        } catch {
            try Task.checkCancellation()
            guard isRunning, generation == operation, refreshID == request,
                  preferences.aiUsageGateway == gateway else { return }
            gatewayDown = true
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
