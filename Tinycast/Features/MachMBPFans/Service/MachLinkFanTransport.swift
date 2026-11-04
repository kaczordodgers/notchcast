import Foundation
import Network

@MainActor
struct MachLinkFanTransport: RemoteFanTransport {
    let channel: MachLinkUsagePeerChannel

    func exchange(_ request: MachLinkMessage) async throws -> MachLinkMessage {
        guard let pairing = channel.pairing else { throw RemoteFanReport.Failure.unavailable }
        let peers = channel.manager.peers.filter {
            guard case let .service(name, _, _, _) = $0.endpoint,
                  name != channel.manager.serviceName,
                  case let .bonjour(record) = $0.metadata else { return false }
            return record["pairing"] == pairing.discoveryHash
        }
        let configuredEndpoint = channel.endpoint
        let endpoints = configuredEndpoint.map { [$0] } ?? peers.map(\.endpoint)
        guard endpoints.count == 1, let endpoint = endpoints.first else {
            throw RemoteFanReport.Failure.unavailable
        }
        let verb = try request.value(as: RemoteFanRequest.self)
        let report = try await MachLinkManager.request(verb, method: request.method,
            from: endpoint, pairing: pairing, as: RemoteFanReport.self)
        guard channel.pairing?.id == pairing.id, channel.endpoint == configuredEndpoint else {
            throw CancellationError()
        }
        return try MachLinkMessage(id: request.id, method: request.method, value: report)
    }
}
