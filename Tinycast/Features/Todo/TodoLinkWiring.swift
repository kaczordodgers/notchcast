import Foundation

extension TodoLinkCoordinator: NotchcastModule {
    func connect(to module: TodoModule) {
        showFailure = module.showFailure
        module.storeDidOpen = { [weak self] in self?.opened($0) }
        module.storeWillClose = { [weak self] in self?.closed() }
        if let store = module.store { opened(store) }
    }

    static func live(channel: MachLinkChannel, preferences: NotchcastPreferences) -> TodoLinkCoordinator {
        let coordinator = TodoLinkCoordinator(enabled: {
            [.tasksSync, .tasks, .machLink].allSatisfy { preferences.isOn($0) }
        }, exchange: { packet in
            try await channel.request(packet, method: "todo-sync", as: TodoLinkPacket.self)
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
