@MainActor
final class RemoteScreenModule: NotchcastModule {
    let coordinator: RemoteScreenCoordinator

    init(channel: MachLinkUsagePeerChannel) {
        coordinator = RemoteScreenCoordinator(transport: { _ in
            guard channel.pairing != nil else { throw MachLinkMessage.Failure.disconnected }
            throw RemoteScreenRequest.Failure.unavailable
        }, open: { _, _ in throw RemoteScreenRequest.Failure.unavailable })
    }

    func start() { coordinator.start() }
    func stop() { coordinator.stop() }
}
