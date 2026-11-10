// notchcast-sources: Tinycast/Features/MachLink/Model/*.swift
// notchcast-kit: root
// notchcast-sources: Tinycast/Features/MachLink/Service/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
import Foundation
import Network

@main
struct MachLinkTest {
    @MainActor
    static func main() async throws {
        let message = try MachLinkMessage(method: "snapshot", value: ["remaining": 42])
        let decoded = try MachLinkMessage.decode(message.encoded())
        precondition(decoded == message)
        let value = try decoded.value(as: [String: Int].self)
        precondition(value == ["remaining": 42])
        print("PASS encode/decode")
        do {
            _ = try MachLinkMessage(method: "snapshot", value: Data(count: 65_536)).encoded()
            fatalError("Oversized message accepted")
        } catch MachLinkMessage.Failure.tooLarge { print("PASS size limit") }

        let pairing = try MachLinkPairing.create()
        precondition(pairing.discoveryHash.count == 24)
        let sameID = try MachLinkPairing(id: pairing.id, secret: Data(count: 32))
        let differentID = try MachLinkPairing.create()
        precondition(pairing.discoveryHash == sameID.discoveryHash)
        precondition(pairing.discoveryHash != differentID.discoveryHash)
        let cancelledConnection = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
        let beforeStart = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await MachLinkTransport.connected(cancelledConnection)
        }
        do {
            try await beforeStart.value
            fatalError("Pre-cancelled connection started")
        } catch is CancellationError { print("PASS cancel before start") }
        let server = MachLinkManager()
        server.register("snapshot") { request in
            try MachLinkMessage(id: request.id, method: request.method, value: ["remaining": 42])
        }
        try server.start(pairing: pairing, name: "Harness")
        defer { server.stop() }
        for _ in 0..<100 where server.port == nil { try await Task.sleep(for: .milliseconds(20)) }
        guard let port = server.port else { fatalError("Listener did not start") }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let result = try await MachLinkManager.request(
            true, method: "snapshot", from: endpoint, pairing: pairing, as: [String: Int].self)
        precondition(result == ["remaining": 42])
        print("PASS loopback request/response")

        do {
            let _: [String: Int] = try await MachLinkManager.request(
                true, method: "snapshot", from: endpoint, pairing: .create(),
                timeout: .seconds(1), as: [String: Int].self)
            fatalError("Unknown peer accepted")
        } catch { print("PASS unknown pairing rejected") }

        do {
            let _: Bool = try await MachLinkManager.request(
                true, method: "snapshot", from: .hostPort(host: "127.0.0.1", port: 1),
                pairing: pairing, timeout: .milliseconds(100), as: Bool.self)
            fatalError("Absent peer answered")
        } catch MachLinkMessage.Failure.timedOut { print("PASS absent peer timeout") }

        let cancelled = Task {
            let _: Bool = try await MachLinkManager.request(
                true, method: "snapshot", from: .hostPort(host: "127.0.0.1", port: 1),
                pairing: pairing, as: Bool.self)
        }
        cancelled.cancel()
        do {
            try await cancelled.value
            fatalError("Cancelled request answered")
        } catch { print("PASS cancellation") }
    }
}
