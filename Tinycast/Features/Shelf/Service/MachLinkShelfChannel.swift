import Foundation

@MainActor
final class MachLinkShelfChannel: ShelfLinkStatus, ShelfTransport {
    let channel: MachLinkChannel
    let status: () -> Bool

    init(channel: MachLinkChannel, module: ShelfModule, status: @escaping () -> Bool) {
        self.channel = channel
        self.status = status
        channel.manager.register(MachLinkMethod.shelfItem.rawValue) { [weak module] request in
            guard NotchcastPreferences.shared.isOn(.machLink), NotchcastPreferences.shared.isOn(.shelfBetweenMacs),
                  let module else { throw MachLinkMessage.Failure.disconnected }
            _ = try await module.receive(request.value(as: ShelfItem.self))
            return try MachLinkMessage(id: request.id, method: request.method, value: true)
        }
    }

    var shelfPeerAvailable: Bool { status() && channel.peer != nil }

    func sendShelfItem(_ item: ShelfItem) async throws {
        guard shelfPeerAvailable else { throw ShelfEngine.Failure.peerDown }
        try ShelfEngine.validate(item)
        guard try await channel.request(item, method: MachLinkMethod.shelfItem.rawValue, as: Bool.self) else {
            throw ShelfEngine.Failure.invalidItem
        }
    }
}
