import Foundation
import Network

@MainActor
final class MachLinkUsagePeerChannel: OtherMacUsagePeerChannel {
    let manager = MachLinkManager()
    var pairing: MachLinkPairing?
    var endpoint: NWEndpoint?

    func requestUsageSnapshot(
        providers: Set<String>, timeout: Duration
    ) async throws -> OtherMacUsageSnapshot {
        guard let pairing else { throw MachLinkMessage.Failure.disconnected }
        let remotes = manager.peers.filter {
            guard case let .service(name, _, _, _) = $0.endpoint else { return false }
            guard name != manager.serviceName, case let .bonjour(record) = $0.metadata else { return false }
            return record["pairing"] == pairing.discoveryHash
        }
        let endpoints = endpoint.map { [$0] } ?? remotes.map(\.endpoint)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        for endpoint in endpoints {
            try Task.checkCancellation()
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw MachLinkMessage.Failure.timedOut }
            do {
                return try await MachLinkManager.request(
                    providers, method: "ai-usage", from: endpoint, pairing: pairing,
                    timeout: min(remaining, .seconds(2)), as: OtherMacUsageSnapshot.self)
            } catch is CancellationError { throw CancellationError() } catch { continue }
        }
        throw MachLinkMessage.Failure.disconnected
    }

    static func response(to request: MachLinkMessage, provider: AIUsageProvider) async throws -> MachLinkMessage {
        guard request.method == "ai-usage" else { throw MachLinkMessage.Failure.invalidMessage }
        let providers = try request.value(as: Set<String>.self)
        let source = AIUsageSnapshotAdapter()
        source.snapshots = await provider.refresh().filter { providers.contains($0.providerID) }
        return try MachLinkMessage(id: request.id, method: request.method, value: await source.localSnapshot())
    }
}
