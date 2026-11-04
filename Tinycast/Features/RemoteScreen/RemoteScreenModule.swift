import AppKit
import Network

@MainActor
final class RemoteScreenModule: NotchcastModule {
    let coordinator: RemoteScreenCoordinator

    init(channel: MachLinkUsagePeerChannel) {
        coordinator = RemoteScreenCoordinator(transport: { message in
            guard let pairing = channel.pairing else { throw MachLinkMessage.Failure.disconnected }
            let peers = channel.manager.peers.filter {
                guard case let .service(name, _, _, _) = $0.endpoint,
                      name != channel.manager.serviceName,
                      case let .bonjour(record) = $0.metadata else { return false }
                return record["pairing"] == pairing.discoveryHash
            }
            let configured = channel.endpoint
            let endpoints = configured.map { [$0] } ?? peers.map(\.endpoint)
            guard endpoints.count == 1, let endpoint = endpoints.first else {
                throw RemoteScreenRequest.Failure.unavailable
            }
            let address = try await MachLinkManager.request(true, method: message.method,
                from: endpoint, pairing: pairing, as: RemoteScreenState.Availability.self)
            guard channel.pairing?.id == pairing.id, channel.endpoint == configured,
                  address.host != nil || !address.screenSharingEnabled else { throw RemoteScreenRequest.Failure.unavailable }
            return try MachLinkMessage(id: message.id, method: message.method, value: address)
        }, open: { url, _ in
            guard NSWorkspace.shared.open(url) else { throw RemoteScreenRequest.Failure.unavailable }
        })
    }

    func start() { coordinator.start() }
    func stop() { coordinator.stop() }
}
