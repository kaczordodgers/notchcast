import Foundation
import Network

@MainActor
final class MachLinkChannel {
    let manager = MachLinkManager()
    var pairing: MachLinkPairing?
    var endpoint: NWEndpoint?

    // Two Macs advertising one pairing are ambiguous, so a request never picks between them.
    var peer: NWEndpoint? {
        if let endpoint { return endpoint }
        guard let pairing else { return nil }
        let paired = manager.peers.filter {
            guard case let .service(name, _, _, _) = $0.endpoint, name != manager.serviceName,
                  case let .bonjour(record) = $0.metadata else { return false }
            return record["pairing"] == pairing.discoveryHash
        }
        return paired.count == 1 ? paired.first?.endpoint : nil
    }

    func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ value: Request, method: String, timeout: Duration = MachLinkRequestBudget.requester,
        as type: Response.Type
    ) async throws -> Response {
        guard let pairing, let peer else { throw MachLinkMessage.Failure.disconnected }
        let destination = endpoint
        let response = try await MachLinkManager.request(
            value, method: method, from: peer, pairing: pairing, timeout: timeout, as: type)
        try Task.checkCancellation()
        guard self.pairing?.id == pairing.id, self.pairing?.secret == pairing.secret,
              endpoint == destination else { throw MachLinkMessage.Failure.disconnected }
        return response
    }
}
