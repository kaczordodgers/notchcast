import AppKit

@MainActor
final class RemoteScreenModule: NotchcastModule {
    /// Set by hub glue in `start` before registrants register; `register` returns [] while nil.
    static var linkChannel: MachLinkChannel?
    let coordinator: RemoteScreenCoordinator
    let launcher = RemoteScreenLauncher()

    init(channel: MachLinkChannel) {
        let launcher = self.launcher
        coordinator = RemoteScreenCoordinator(transport: { message in
            let address = try await channel.request(true, method: message.method,
                as: RemoteScreenState.Availability.self)
            guard address.host != nil || !address.screenSharingEnabled else { throw RemoteScreenRequest.Failure.unavailable }
            return try MachLinkMessage(id: message.id, method: message.method, value: address)
        }, open: { url, client in
            try await launcher.open(url, client: client)
        })
        channel.manager.register(MachLinkMethod.remoteScreenAvailability.rawValue) { request in
            try await RemoteScreenCoordinator.peerResponse(to: request, enabled: {
                NotchcastPreferences.shared.isEnabled(.remoteScreen)
            }, address: { try await RemoteScreenAddress.current() })
        }
    }

    func start() { coordinator.start() }
    func stop() { coordinator.stop() }
}
