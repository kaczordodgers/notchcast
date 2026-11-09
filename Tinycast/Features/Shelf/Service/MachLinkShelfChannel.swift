import Foundation

@MainActor
final class MachLinkShelfChannel: ShelfLinkStatus, ShelfTransport {
    let channel: MachLinkChannel
    let status: () -> Bool

    init(channel: MachLinkChannel, status: @escaping () -> Bool) {
        self.channel = channel
        self.status = status
    }

    var shelfPeerAvailable: Bool { status() && channel.peer != nil }

    func sendShelfItem(_ item: ShelfItem) async throws {
        guard shelfPeerAvailable else { throw ShelfEngine.Failure.peerDown }
        try ShelfEngine.validate(item)
        guard try await channel.request(item, method: "shelf-item", as: Bool.self) else {
            throw ShelfEngine.Failure.invalidItem
        }
    }
}
