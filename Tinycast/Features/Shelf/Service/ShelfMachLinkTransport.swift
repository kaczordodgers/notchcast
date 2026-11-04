import Foundation
import Network

@MainActor
final class ShelfMachLinkTransport: ShelfTransport {
    let endpoint: NWEndpoint
    let pairing: MachLinkPairing

    init(endpoint: NWEndpoint, pairing: MachLinkPairing) {
        self.endpoint = endpoint
        self.pairing = pairing
    }

    func sendShelfItem(_ item: ShelfItem) async throws {
        try ShelfEngine.validate(item)
        let accepted = try await MachLinkManager.request(
            item, method: "shelf-item", from: endpoint, pairing: pairing, as: Bool.self)
        guard accepted else { throw ShelfEngine.Failure.invalidItem }
    }

    static func response(to request: MachLinkMessage, module: ShelfModule) async throws -> MachLinkMessage {
        guard request.method == "shelf-item" else { throw MachLinkMessage.Failure.invalidMessage }
        _ = try await module.receive(request.value(as: ShelfItem.self))
        return try MachLinkMessage(id: request.id, method: request.method, value: true)
    }
}
