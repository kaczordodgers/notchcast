import Foundation
import Network

@MainActor
struct FleetMachLinkTransport: FleetTransport {
    let channel: MachLinkUsagePeerChannel

    func read() async throws -> FleetSnapshot {
        guard NotchcastPreferences.shared.isOn(.machLink), let pairing = channel.pairing else {
            throw MachLinkMessage.Failure.disconnected
        }
        let peers = channel.manager.peers.filter {
            guard case let .service(name, _, _, _) = $0.endpoint,
                  name != channel.manager.serviceName,
                  case let .bonjour(record) = $0.metadata else { return false }
            return record["pairing"] == pairing.discoveryHash
        }
        let configuredEndpoint = channel.endpoint
        let endpoints = configuredEndpoint.map { [$0] } ?? peers.map(\.endpoint)
        guard endpoints.count == 1, let endpoint = endpoints.first else {
            throw MachLinkMessage.Failure.disconnected
        }
        let snapshot = try await MachLinkManager.request(true, method: "agent-threads",
            from: endpoint, pairing: pairing, as: FleetSnapshot.self)
        guard channel.pairing?.id == pairing.id, channel.endpoint == configuredEndpoint else {
            throw CancellationError()
        }
        return snapshot
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
