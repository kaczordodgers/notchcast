import Foundation

@MainActor protocol OtherMacUsageSnapshotSource {
    func localSnapshot() async throws -> OtherMacUsageSnapshot
}

@MainActor protocol OtherMacUsagePeerChannel {
    // Implementations stop owned IO on cancellation or deadline, and return local-only data.
    func requestUsageSnapshot(
        providers: Set<String>, timeout: Duration
    ) async throws -> OtherMacUsageSnapshot
}

@MainActor final class OtherMacUsageService {
    enum PeerStatus: Equatable {
        case disabled, missing, available, failed
    }

    private(set) var peerStatus: PeerStatus = .missing
    private(set) var localFailed = false
    private var local: OtherMacUsageSnapshot?
    private var peer: OtherMacUsageSnapshot?
    private var lastRequest: Date?
    private var isRefreshing = false
    private var generation = 0
    private let source: any OtherMacUsageSnapshotSource
    private let channel: any OtherMacUsagePeerChannel
    private let clock: () -> Date
    private var providers: Set<String> = []
    private var peerEnabled = false

    init(
        source: any OtherMacUsageSnapshotSource, channel: any OtherMacUsagePeerChannel,
        clock: @escaping () -> Date
    ) {
        self.source = source
        self.channel = channel
        self.clock = clock
    }

    func configure(peerEnabled: Bool, providers: Set<String>) {
        guard self.peerEnabled != peerEnabled || self.providers != providers else { return }
        generation += 1
        lastRequest = nil
        self.peerEnabled = peerEnabled
        self.providers = providers
        peer = nil
        peerStatus = peerEnabled ? .missing : .disabled
    }

    func readings(maximumAge: TimeInterval = OtherMacUsageSnapshot.staleAfter) -> [OtherMacUsageEngine.Reading] {
        OtherMacUsageEngine.merge(
            local: local, peer: peer, now: clock(), maximumAge: maximumAge,
            peerFailed: peerStatus == .failed, localFailed: localFailed
        ).filter { providers.contains($0.value.providerID) }
    }

    func refresh() async throws {
        guard !isRefreshing else { return }
        try Task.checkCancellation()
        isRefreshing = true
        defer { isRefreshing = false }
        let operation = generation
        do {
            let snapshot = try await source.localSnapshot()
            try Task.checkCancellation()
            guard generation == operation else { return }
            local = snapshot
            localFailed = false
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            guard generation == operation else { return }
            localFailed = true
        }
        guard peerEnabled, !providers.isEmpty else { return }
        let now = clock()
        if let lastRequest, now.timeIntervalSince(lastRequest) < 60 { return }
        lastRequest = now
        do {
            let snapshot = try await channel.requestUsageSnapshot(providers: providers, timeout: .seconds(20))
            try Task.checkCancellation()
            guard generation == operation else { return }
            peer = snapshot
            peerStatus = .available
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            guard generation == operation else { return }
            peerStatus = .failed
        }
    }
}
