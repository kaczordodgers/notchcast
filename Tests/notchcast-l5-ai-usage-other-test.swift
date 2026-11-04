// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Service/*.swift
import Foundation

@MainActor private final class Source: OtherMacUsageSnapshotSource {
    var snapshot = OtherMacUsageSnapshot(readings: [])
    func localSnapshot() async throws -> OtherMacUsageSnapshot { snapshot }
}

@MainActor private final class Channel: OtherMacUsagePeerChannel {
    enum Failure: Error { case timeout }
    var snapshot = OtherMacUsageSnapshot(readings: [])
    var fails = false
    var requests = 0
    var requestedProviders: Set<String> = []
    var beforeReturn: (() -> Void)?
    var cancels = false
    func requestUsageSnapshot(
        providers: Set<String>, timeout: Duration
    ) async throws -> OtherMacUsageSnapshot {
        precondition(timeout == .seconds(20))
        requests += 1
        requestedProviders = providers
        beforeReturn?()
        if cancels { throw CancellationError() }
        if fails { throw Failure.timeout }
        return snapshot
    }
}

@main struct OtherMacUsageTest {
    @MainActor static func main() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        func snapshot(_ plan: String, _ used: Double, _ age: Double = 0) -> OtherMacUsageSnapshot {
            OtherMacUsageSnapshot(readings: [.init(
                providerID: "provider", planID: plan, windowID: "weekly", usedFraction: used,
                observedAt: now.addingTimeInterval(-age)
            )])
        }
        func merge(_ local: OtherMacUsageSnapshot?, _ peer: OtherMacUsageSnapshot?) -> [OtherMacUsageEngine.Reading] {
            OtherMacUsageEngine.merge(local: local, peer: peer, now: now, maximumAge: 300)
        }
        let local = snapshot("shared", 0.4, 10)
        let remote = snapshot("shared", 0.5)
        precondition(merge(local, remote).count == 1)
        precondition(merge(local, remote)[0].value.usedFraction == 0.5)
        precondition(merge(local, snapshot("different", 0.2)).count == 2)
        precondition(merge(local, nil).count == 1)
        precondition(merge(nil, remote).count == 1)
        precondition(merge(nil, nil).isEmpty)
        precondition(merge(nil, snapshot("old", 0.2, 301))[0].isStale)
        precondition(merge(nil, snapshot("boundary", 0.2, 300))[0].isStale)
        var stale = remote
        stale.readings[0].isStale = true
        precondition(merge(nil, stale)[0].isStale)
        let source = Source()
        source.snapshot = local
        let channel = Channel()
        channel.snapshot = remote
        let service = OtherMacUsageService(source: source, channel: channel, clock: { now })
        service.configure(peerEnabled: true, providers: ["provider"])
        try await service.refresh()
        precondition(service.peerStatus == .available && channel.requests == 1)
        precondition(channel.requestedProviders == ["provider"])
        try await service.refresh()
        precondition(channel.requests == 1)
        service.configure(peerEnabled: false, providers: ["provider"])
        service.configure(peerEnabled: true, providers: ["provider"])
        try await service.refresh()
        precondition(channel.requests == 2)
        now = now.addingTimeInterval(60)
        channel.fails = true
        try await service.refresh()
        precondition(service.peerStatus == .failed && channel.requests == 3)
        precondition(service.readings()[0].value.usedFraction == 0.4)
        source.snapshot = OtherMacUsageSnapshot(readings: [])
        now = now.addingTimeInterval(60)
        try await service.refresh()
        precondition(service.readings()[0].isStale)
        precondition(service.readings()[0].value.usedFraction == 0.5)
        service.configure(peerEnabled: false, providers: ["provider"])
        now = now.addingTimeInterval(60)
        try await service.refresh()
        precondition(channel.requests == 4 && service.readings().isEmpty)
        service.configure(peerEnabled: true, providers: ["provider"])
        channel.fails = false
        channel.beforeReturn = { service.configure(peerEnabled: false, providers: ["provider"]) }
        try await service.refresh()
        precondition(service.peerStatus == .disabled && service.readings().isEmpty)
        now = now.addingTimeInterval(60)
        service.configure(peerEnabled: true, providers: ["provider"])
        channel.beforeReturn = nil
        channel.cancels = true
        do {
            try await service.refresh()
            preconditionFailure("Cancellation must propagate")
        } catch is CancellationError {}
        print("PASS: shared/different/missing plans, freshness, timeout retention, throttle, disabled peer")
    }
}
