import Foundation

extension TodoLinkCoordinator: NotchcastModule {
    func connect(to module: TodoModule) {
        showFailure = module.showFailure
        module.storeDidOpen = { [weak self] in self?.opened($0) }
        module.storeWillClose = { [weak self] in self?.closed() }
        if let store = module.store { opened(store) }
    }

    static func live(channel: MachLinkUsagePeerChannel, preferences: NotchcastPreferences) -> TodoLinkCoordinator {
        let coordinator = TodoLinkCoordinator(enabled: {
            [.tasksSync, .tasks, .machLink].allSatisfy { preferences.isOn($0) }
        }, exchange: { packet in
            guard let pairing = channel.pairing else { throw MachLinkMessage.Failure.disconnected }
            let peers = channel.manager.peers.filter {
                guard case let .service(name, _, _, _) = $0.endpoint,
                      name != channel.manager.serviceName,
                      case let .bonjour(record) = $0.metadata else { return false }
                return record["pairing"] == pairing.discoveryHash
            }
            let endpoints = channel.endpoint.map { [$0] } ?? peers.map(\.endpoint)
            let destination = channel.endpoint
            for endpoint in endpoints {
                try Task.checkCancellation()
                do {
                    let response = try await MachLinkManager.request(packet, method: "todo-sync", from: endpoint,
                        pairing: pairing, as: TodoLinkPacket.self)
                    try Task.checkCancellation()
                    guard channel.pairing?.id == pairing.id, channel.pairing?.secret == pairing.secret,
                          channel.endpoint == destination else {
                        throw TodoLinkPacket.Failure.unavailable
                    }
                    return response
                } catch is CancellationError { throw CancellationError() } catch { continue }
            }
            throw MachLinkMessage.Failure.disconnected
        })
        coordinator.pairingIdentity = { channel.pairing?.id }
        return coordinator
    }

    func response(to request: MachLinkMessage) throws -> MachLinkMessage {
        let response = try respond(request.value(as: TodoLinkPacket.self))
        return try MachLinkMessage(id: request.id, method: request.method, value: response)
    }

    func peerResponse(to request: MachLinkMessage, via manager: MachLinkManager) async throws -> MachLinkMessage? {
        try await manager.todoResponse(to: request, enabled: { self.canSync }, handler: {
            try self.response(to: $0)
        })
    }
}
