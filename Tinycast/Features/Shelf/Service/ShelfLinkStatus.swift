import Foundation

@MainActor
protocol ShelfLinkStatus: AnyObject {
    var shelfPeerAvailable: Bool { get }
}

@MainActor
protocol ShelfTransport: AnyObject {
    func sendShelfItem(_ item: ShelfItem) async throws
}
