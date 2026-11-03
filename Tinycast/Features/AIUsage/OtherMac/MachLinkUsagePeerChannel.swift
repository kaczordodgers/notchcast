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
        let remote = manager.peers.first {
            guard case let .service(name, _, _, _) = $0.endpoint else { return false }
            return name != ProcessInfo.processInfo.hostName
        }?.endpoint
        guard let pairing, let endpoint = endpoint ?? remote else {
            throw MachLinkMessage.Failure.disconnected
        }
        return try await MachLinkManager.request(
            providers, method: "ai-usage", from: endpoint, pairing: pairing,
            timeout: timeout, as: OtherMacUsageSnapshot.self)
    }

    static func response(to request: MachLinkMessage, provider: AIUsageProvider) async throws -> MachLinkMessage {
        guard request.method == "ai-usage" else { throw MachLinkMessage.Failure.invalidMessage }
        let providers = try request.value(as: Set<String>.self)
        let source = AIUsageSnapshotAdapter()
        source.snapshots = await provider.refresh().filter { providers.contains($0.providerID) }
        return try MachLinkMessage(id: request.id, method: request.method, value: await source.localSnapshot())
    }
}
