// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/MachLink/Service/MachLinkManager+Peers.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Service/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
import Foundation

@MainActor final class MachLinkManager {
    var fanHandler: ((RemoteFanRequest) async throws -> RemoteFanReport)?
    var fanEnabled: () -> Bool = { true }
    var screenAddress: () async throws -> RemoteScreenState.Availability = {
        .init(screenSharingEnabled: true, host: "real-peer.local")
    }
}

@main struct ScreenPeerTest {
    @MainActor static func main() async throws {
        let peer = MachLinkManager()
        var opened: [URL] = []
        let coordinator = RemoteScreenCoordinator(transport: { request in
            try await peer.peerResponse(to: request)!
        }, open: { url, _ in opened.append(url) })
        coordinator.start()
        try await coordinator.show(.init(host: "unused.local"), preferredClientInstalled: false)
        precondition(opened.map(\.absoluteString) == ["vnc://real-peer.local"])
        peer.screenAddress = { .init(screenSharingEnabled: false) }
        do {
            try await coordinator.show(.init(host: "unused.local"), preferredClientInstalled: false)
            fatalError("Sharing off accepted")
        } catch RemoteScreenRequest.Failure.unavailable {}
        precondition(opened.count == 1)
        print("PASS peer address, sharing-off refusal, fake opener vnc URL")
    }
}
