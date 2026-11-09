import Foundation

@MainActor
struct MachLinkFanTransport: RemoteFanTransport {
    let channel: MachLinkChannel

    func exchange(_ request: MachLinkMessage) async throws -> MachLinkMessage {
        let verb = try request.value(as: RemoteFanRequest.self)
        let report = try await channel.request(verb, method: request.method, as: RemoteFanReport.self)
        return try MachLinkMessage(id: request.id, method: request.method, value: report)
    }
}
