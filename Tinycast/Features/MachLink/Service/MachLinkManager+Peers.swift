import Foundation

extension MachLinkManager {
    func todoResponse(to request: MachLinkMessage, enabled: @MainActor () -> Bool,
                      handler: @MainActor (MachLinkMessage) async throws -> MachLinkMessage) async throws -> MachLinkMessage? {
        guard request.method == "todo-sync" else { return nil }
        try Task.checkCancellation()
        guard enabled() else { throw MachLinkMessage.Failure.disconnected }
        let response = try await handler(request)
        try Task.checkCancellation()
        guard enabled() else { throw MachLinkMessage.Failure.disconnected }
        guard response.id == request.id, response.method == request.method else {
            throw MachLinkMessage.Failure.invalidMessage
        }
        return response
    }

    func peerResponse(to request: MachLinkMessage) async throws -> MachLinkMessage? {
        switch request.method {
        case "mbp-fans":
            guard fanEnabled(), let fanHandler else { throw RemoteFanReport.Failure.unavailable }
            let report = try await fanHandler(request.value(as: RemoteFanRequest.self))
            try Task.checkCancellation()
            guard fanEnabled() else { throw RemoteFanReport.Failure.unavailable }
            return try MachLinkMessage(id: request.id, method: request.method, value: report)
        case "remote-screen-availability":
            _ = try request.value(as: Bool.self)
            let address = screenEnabled()
                ? try await screenAddress()
                : RemoteScreenState.Availability(screenSharingEnabled: false, peerEnabled: false)
            try Task.checkCancellation()
            let result = screenEnabled() ? address
                : RemoteScreenState.Availability(screenSharingEnabled: false, peerEnabled: false)
            return try MachLinkMessage(id: request.id, method: request.method, value: result)
        default: return nil
        }
    }
}
