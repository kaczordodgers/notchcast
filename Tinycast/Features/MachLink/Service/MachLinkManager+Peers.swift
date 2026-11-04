import Foundation

extension MachLinkManager {
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
