import Foundation

extension RemoteScreenCoordinator {
    static func peerResponse(
        to request: MachLinkMessage, enabled: () -> Bool,
        address: () async throws -> RemoteScreenState.Availability
    ) async throws -> MachLinkMessage {
        _ = try request.value(as: Bool.self)
        let off = RemoteScreenState.Availability(screenSharingEnabled: false, peerEnabled: false)
        let current = try await enabled() ? address() : off
        try Task.checkCancellation()
        return try MachLinkMessage(id: request.id, method: request.method, value: enabled() ? current : off)
    }
}
