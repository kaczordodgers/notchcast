// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Service/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/RemoteScreenAddress.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation

@main struct ScreenPeerTest {
    @MainActor static func main() async throws {
        let availability = try await RemoteScreenAddress.current()
        precondition(!availability.screenSharingEnabled || availability.host != nil)
        var enabled = true
        var address: () async throws -> RemoteScreenState.Availability = {
            .init(screenSharingEnabled: true, host: "real-peer.local")
        }
        var opened: [URL] = []
        let coordinator = RemoteScreenCoordinator(transport: { request in
            try await RemoteScreenCoordinator.peerResponse(to: request, enabled: { enabled }, address: address)
        }, open: { url, _ in opened.append(url) })
        coordinator.start()
        try await coordinator.show(.init(host: "unused.local"), preferredClientInstalled: false)
        precondition(opened.map(\.absoluteString) == ["vnc://real-peer.local"])
        address = { .init(screenSharingEnabled: false) }
        do {
            try await coordinator.show(.init(host: "unused.local"), preferredClientInstalled: false)
            fatalError("Sharing off accepted")
        } catch RemoteScreenRequest.Failure.sharingDisabled {}
        precondition(opened.count == 1)
        enabled = false
        address = { fatalError("Disabled peer queried sharing") }
        do {
            try await coordinator.show(.init(host: "unused.local"), preferredClientInstalled: false)
            fatalError("Disabled peer accepted")
        } catch RemoteScreenRequest.Failure.peerDisabled {}
        print("PASS peer address, sharing-off refusal, fake opener vnc URL")
    }
}
