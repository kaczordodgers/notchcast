import AppKit

@MainActor
final class RemoteScreenModule: NotchcastModule {
    /// Hub glue sets this before modules register, so the registration names no Mac Link type.
    static var linkChannel: MachLinkChannel?
    let coordinator: RemoteScreenCoordinator

    init(channel: MachLinkChannel) {
        coordinator = RemoteScreenCoordinator(transport: { message in
            let address = try await channel.request(true, method: message.method,
                as: RemoteScreenState.Availability.self)
            guard address.host != nil || !address.screenSharingEnabled else { throw RemoteScreenRequest.Failure.unavailable }
            return try MachLinkMessage(id: message.id, method: message.method, value: address)
        }, open: { url, _ in
            guard NSWorkspace.shared.open(url) else { throw RemoteScreenRequest.Failure.unavailable }
        })
        channel.manager.register("remote-screen-availability") { request in
            try await RemoteScreenCoordinator.peerResponse(to: request, enabled: {
                [.machLink, .remoteScreen].allSatisfy { NotchcastPreferences.shared.isOn($0) }
            }, address: { try await RemoteScreenAddress.current() })
        }
    }

    func start() { coordinator.start() }
    func stop() { coordinator.stop() }
}
