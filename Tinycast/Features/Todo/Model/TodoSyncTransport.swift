import Foundation

@MainActor
protocol TodoSyncTransport {
    func send(_ envelopes: [TodoEnvelope]) throws
    func receive() throws -> [TodoEnvelope]
}

@MainActor
final class TodoFakeSyncTransport: TodoSyncTransport {
    private var inbox: [TodoEnvelope] = []
    private weak var peer: TodoFakeSyncTransport?

    enum Failure: Error { case disconnected }

    static func pair() -> (TodoFakeSyncTransport, TodoFakeSyncTransport) {
        let first = TodoFakeSyncTransport()
        let second = TodoFakeSyncTransport()
        first.peer = second
        second.peer = first
        return (first, second)
    }

    func send(_ envelopes: [TodoEnvelope]) throws {
        guard let peer else { throw Failure.disconnected }
        peer.inbox.append(contentsOf: envelopes)
    }

    func receive() -> [TodoEnvelope] {
        let pending = inbox
        inbox.removeAll()
        return pending
    }
}
