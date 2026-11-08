import Foundation

@MainActor
final class ShelfModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var generation = UUID()
    var linkStatus: (any ShelfLinkStatus)?
    var transport: (any ShelfTransport)?
    let store: ShelfReceivedStore
    private var receiving = false

    init(directory: URL = URL.cachesDirectory
        .appendingPathComponent(NotchcastIdentity.current.bundleID)
        .appendingPathComponent("shelf-received")) {
        store = ShelfReceivedStore(directory: directory)
    }

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        generation = UUID()
    }

    func send(_ item: ShelfItem) async throws {
        try ShelfEngine.validate(item)
        guard isRunning else { throw ShelfEngine.Failure.stopped }
        guard linkStatus?.shelfPeerAvailable == true, let transport else { throw ShelfEngine.Failure.peerDown }
        let operation = generation
        try await transport.sendShelfItem(item)
        try Task.checkCancellation()
        guard isRunning, generation == operation else { throw ShelfEngine.Failure.stopped }
    }

    func receive(_ item: ShelfItem) async throws -> URL {
        guard isRunning else { throw ShelfEngine.Failure.stopped }
        guard !receiving else { throw ShelfEngine.Failure.full }
        receiving = true
        defer { receiving = false }
        let operation = generation
        let url = try await store.receive(item)
        try Task.checkCancellation()
        guard isRunning, generation == operation else { throw ShelfEngine.Failure.stopped }
        return url
    }
}
