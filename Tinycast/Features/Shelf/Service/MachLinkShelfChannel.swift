import Foundation
import Network

@MainActor
final class MachLinkShelfChannel: ShelfLinkStatus, ShelfTransport {
    let channel: MachLinkUsagePeerChannel
    let status: () -> Bool

    init(channel: MachLinkUsagePeerChannel, status: @escaping () -> Bool) {
        self.channel = channel
        self.status = status
    }

    var shelfPeerAvailable: Bool { status() && channel.pairing != nil && endpoint != nil }

    private var endpoint: NWEndpoint? {
        if let endpoint = channel.endpoint { return endpoint }
        return channel.manager.peers.first {
            guard case let .service(name, _, _, _) = $0.endpoint,
                  name != channel.manager.serviceName, case let .bonjour(record) = $0.metadata else { return false }
            return record["pairing"] == channel.pairing?.discoveryHash
        }?.endpoint
    }

    func sendShelfItem(_ item: ShelfItem) async throws {
        guard shelfPeerAvailable, let endpoint, let pairing = channel.pairing else {
            throw ShelfEngine.Failure.peerDown
        }
        try await ShelfMachLinkTransport(endpoint: endpoint, pairing: pairing).sendShelfItem(item)
    }
}
