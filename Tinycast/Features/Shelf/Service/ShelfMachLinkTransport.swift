import Foundation

@MainActor
enum ShelfMachLinkTransport {
    static func response(to request: MachLinkMessage, module: ShelfModule) async throws -> MachLinkMessage {
        guard request.method == "shelf-item" else { throw MachLinkMessage.Failure.invalidMessage }
        _ = try await module.receive(request.value(as: ShelfItem.self))
        return try MachLinkMessage(id: request.id, method: request.method, value: true)
    }
}
