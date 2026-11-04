import Foundation
import Observation

@MainActor
final class AIUsageModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var snapshots: [AIUsageSnapshot] = []
    let otherMac: OtherMacUsageService
    private let provider: AIUsageProvider?
    private let post: @MainActor (String) -> Void
    private let source: AIUsageSnapshotAdapter
    private let preferences: NotchcastPreferences
    private var generation = 0
    private var refreshing = false

    var peerStatus: String {
        otherMac.peerStatus == .available ? String(localized: "Connected") : String(localized: "Not connected")
    }

    init(
        provider: AIUsageProvider? = nil,
        preferences: NotchcastPreferences = .shared,
        channel: MachLinkUsagePeerChannel = MachLinkUsagePeerChannel(),
        post: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.provider = provider
        self.post = post
        self.preferences = preferences
        let source = AIUsageSnapshotAdapter()
        self.source = source
        otherMac = OtherMacUsageService(source: source, channel: channel, clock: { Date() })
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
        source.snapshots = []
        otherMac.configure(peerEnabled: false, providers: [])
    }

    func refresh() async throws {
        guard isRunning, !refreshing else { return }
        let provider = provider ?? AIUsageProvider(cacheDirectory: AIUsageProvider.cacheDirectory(
            path: preferences.aiUsageCachePath, homeDirectory: FileManager.default.homeDirectoryForCurrentUser))
        refreshing = true
        defer { refreshing = false }
        let operation = generation
        let values = await provider.refresh()
        try Task.checkCancellation()
        guard isRunning, generation == operation else { return }
        snapshots = values
        source.snapshots = values
        configurePeer()
        try await otherMac.refresh()
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
            peerEnabled: preferences.isOn(.aiUsageOtherMac) && preferences.isOn(.machLink),
            providers: Set(snapshots.map(\.providerID).filter { !$0.isEmpty }))
    }
}
