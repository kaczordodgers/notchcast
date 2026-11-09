import Foundation

@MainActor
struct FleetMachLinkTransport: FleetTransport {
    let channel: MachLinkChannel

    init(channel: MachLinkChannel) {
        self.channel = channel
        channel.manager.register("agent-threads") { try await Self.response(to: $0) }
    }

    func read() async throws -> FleetSnapshot {
        guard NotchcastPreferences.shared.isOn(.machLink) else { throw MachLinkMessage.Failure.disconnected }
        return try await channel.request(true, method: "agent-threads", as: FleetSnapshot.self)
    }

    static func response(to request: MachLinkMessage) async throws -> MachLinkMessage {
        try await response(to: request, linkEnabled: NotchcastPreferences.shared.isOn(.machLink),
            featureEnabled: NotchcastPreferences.shared.isOn(.fleetPanel), read: { await FleetLocalSource.read() })
    }

    static func response(to request: MachLinkMessage, linkEnabled: Bool, featureEnabled: Bool,
                         timeout: Duration = .seconds(20),
                         read: @escaping @MainActor () async -> FleetSnapshot) async throws -> MachLinkMessage {
        guard linkEnabled else { throw MachLinkMessage.Failure.disconnected }
        guard request.method == "agent-threads", try request.value(as: Bool.self) else {
            throw MachLinkMessage.Failure.invalidMessage
        }
        let snapshot = featureEnabled ? await boundedRead(timeout: timeout, read: read)
            : FleetSnapshot(rows: [], failure: .off)
        return try MachLinkMessage(id: request.id, method: request.method, value: snapshot)
    }

    private static func boundedRead(timeout: Duration,
                                    read: @escaping @MainActor () async -> FleetSnapshot) async -> FleetSnapshot {
        let (results, continuation) = AsyncStream<FleetSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let reading = Task {
            let snapshot = await read()
            guard !Task.isCancelled else { return }
            continuation.yield(snapshot)
            continuation.finish()
        }
        let deadline = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            continuation.yield(.init(rows: [], failure: .failed))
            continuation.finish()
        }
        defer { reading.cancel(); deadline.cancel(); continuation.finish() }
        var iterator = results.makeAsyncIterator()
        return await iterator.next() ?? .init(rows: [], failure: .failed)
    }
}
