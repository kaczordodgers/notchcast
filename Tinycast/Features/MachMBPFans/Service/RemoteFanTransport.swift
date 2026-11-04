import Foundation

@MainActor
protocol RemoteFanTransport {
    func exchange(_ request: MachLinkMessage) async throws -> MachLinkMessage
}
