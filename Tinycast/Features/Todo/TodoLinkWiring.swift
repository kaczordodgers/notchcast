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
            do {
                return try await channel.request(packet, method: MachLinkMethod.todoSync.rawValue, as: TodoLinkPacket.self)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MachLinkMessage.Failure.disconnected
            }
        })
        coordinator.pairingIdentity = { channel.pairing?.id }
        channel.manager.register(MachLinkMethod.todoSync.rawValue) { [weak coordinator] request in
            guard let coordinator else { throw MachLinkMessage.Failure.disconnected }
            return try coordinator.response(to: request)
        }
        return coordinator
    }

    func response(to request: MachLinkMessage) throws -> MachLinkMessage {
        try Task.checkCancellation()
        guard canSync else { throw MachLinkMessage.Failure.disconnected }
        let response = try respond(request.value(as: TodoLinkPacket.self))
        return try MachLinkMessage(id: request.id, method: request.method, value: response)
    }
}
