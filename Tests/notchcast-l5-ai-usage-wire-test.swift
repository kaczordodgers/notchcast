// notchcast-sources: Tinycast/Features/AIUsage/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/Service/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Service/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/AIUsageModule.swift
// notchcast-sources: Tinycast/Features/MachLink/AIUsageLinkModule.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/*.swift
// notchcast-kit: root core
// notchcast-sources: Tinycast/Features/MachLink/Service/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
import Foundation
import Network

@MainActor
final class QuotaHTTPServer {
    private let listener: NWListener
    private var isReady = false
    private var connections: [NWConnection] = []
    private var pending: [NWConnection] = []
    private(set) var requests = 0
    var status = 200
    var body = Data()
    var holdsResponses = false

    var address: String { "http://127.0.0.1:\(listener.port!.rawValue)" }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                connections.append(connection)
                connection.start(queue: .main)
                receive(connection, bytes: Data())
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .ready = state { self?.isReady = true }
            }
        }
        listener.start(queue: .main)
    }

    func waitUntilReady() async throws {
        for _ in 0..<1_000 where !isReady { try await Task.sleep(for: .milliseconds(10)) }
        precondition(isReady && listener.port?.rawValue != 0, "HTTP fixture did not start")
    }

    func waitForRequest(after count: Int) async throws {
        for _ in 0..<1_000 where requests <= count { try await Task.sleep(for: .milliseconds(10)) }
        precondition(requests > count, "Real HTTP request did not reach the fixture after request \(count)")
    }

    func release() {
        holdsResponses = false
        for connection in pending { respond(connection) }
        pending = []
    }

    func stop() {
        listener.cancel()
        for connection in connections { connection.cancel() }
    }

    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, done, error in
            Task { @MainActor [weak self] in
                guard let self, let data, error == nil else { connection.cancel(); return }
                let received = bytes + data
                if let text = String(data: received, encoding: .utf8), text.contains("\r\n\r\n") {
                    precondition(text.hasPrefix("GET /v1/magpie/quotas HTTP/1.1"))
                    requests += 1
                    if holdsResponses { pending.append(connection) } else { respond(connection) }
                } else if !done {
                    receive(connection, bytes: received)
                } else { connection.cancel() }
            }
        }
    }

    private func respond(_ connection: NWConnection) {
        let headers = "HTTP/1.1 \(status) Fixture\r\nContent-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

@main
struct AIUsageWiringTest {
    @MainActor static func main() async throws {
        let suite = "ai-usage-wire-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(preferences.aiUsageGateway == "http://127.0.0.1:3425")
        precondition(!preferences.isEnabled(.aiUsageOtherMac))
        let http = try QuotaHTTPServer()
        defer { http.stop() }
        try await http.waitUntilReady()
        var now = try Date("2026-11-12T12:00:00Z", strategy: .iso8601)
        http.body = Data("""
        {"object":"list","data":[{"provider":"fixture","name":"Account A","plan":"pro",
        "windows":[{"name":"Session","used":42,"resetsAt":"2026-11-12T12:00:30Z"}],
        "readAt":"2026-11-12T12:00:00Z"}]}
        """.utf8)
        preferences.aiUsageGateway = http.address + " \n"
        let channel = MachLinkChannel()
        let module = AIUsageModule(preferences: preferences, channel: channel, clock: { now })
        let link = AIUsageLinkModule(defaults: defaults)
        let controller = NotchcastModuleController([
            .init(requires: [.aiUsage], module: module),
            .init(requires: [.machLink], module: link),
        ], preferences: preferences)
        controller.run()
        try await module.refresh()
        precondition(!module.isRunning && http.requests == 0)
        preferences.set(.aiUsage, true)
        for _ in 0..<30 { await Task.yield() }
        precondition(module.isRunning && module.refreshedAt == nil && module.needsRefresh)
        http.holdsResponses = true
        let initial = Task { try await module.refresh() }
        try await http.waitForRequest(after: 0)
        precondition(module.isLoading && module.refreshedAt == nil)
        http.release()
        try await initial.value
        precondition(!module.isLoading && !module.gatewayDown && !module.needsRefresh)
        precondition(module.snapshots.first?.windows.first?.percentLeft == 58)
        now = now.addingTimeInterval(31)
        precondition(module.needsRefresh, "Crossing a reset refreshes before the 60-second age limit")
        try await module.refresh()
        precondition(!module.needsRefresh, "An already-passed reset does not cause repeated fetches")

        http.status = 503
        try await module.refresh()
        precondition(module.gatewayDown && module.snapshots.isEmpty && !module.isLoading)
        precondition(module.refreshedAt == nil && module.needsRefresh,
                     "A failure invalidates recent success so reopening retries immediately")
        http.status = 200
        http.holdsResponses = true
        let retryCount = http.requests
        let retry = Task { try await module.refresh() }
        try await http.waitForRequest(after: retryCount)
        precondition(module.isLoading && module.refreshedAt == nil,
                     "Retry shows loading even after an earlier successful fetch")
        http.release()
        try await retry.value
        precondition(!module.gatewayDown && !module.isLoading && !module.needsRefresh)
        precondition(module.snapshots.first?.accountName == "Account A")
        http.body = Data(#"{"object":"list","data":[]}"#.utf8)
        preferences.aiUsageGateway = http.address.replacingOccurrences(of: "http://", with: "")
        try await module.refresh()
        precondition(!module.gatewayDown && module.snapshots.isEmpty && module.refreshedAt != nil)

        let replacement = try QuotaHTTPServer()
        defer { replacement.stop() }
        try await replacement.waitUntilReady()
        replacement.body = Data("""
        {"object":"list","data":[{"provider":"fixture","name":"Account B","plan":"team",
        "windows":[{"name":"Weekly","used":15}],"readAt":"2026-11-12T12:00:00Z"}]}
        """.utf8)
        http.holdsResponses = true
        let count = http.requests
        let old = Task { try await module.refresh() }
        try await http.waitForRequest(after: count)
        preferences.aiUsageGateway = replacement.address
        try await module.refresh()
        precondition(module.snapshots.first?.accountName == "Account B")
        http.release()
        try await old.value
        precondition(module.snapshots.first?.accountName == "Account B" && !module.gatewayDown)

        http.status = 503
        http.holdsResponses = true
        preferences.aiUsageGateway = http.address
        let failedCount = http.requests
        let obsoleteFailure = Task { try await module.refresh() }
        try await http.waitForRequest(after: failedCount)
        preferences.aiUsageGateway = replacement.address
        http.release()
        try await obsoleteFailure.value
        precondition(!module.gatewayDown && module.snapshots.first?.accountName == "Account B")

        let pairing = try MachLinkPairing.create()
        preferences.set(.aiUsageOtherMac, true)
        preferences.set(.machLink, true)
        try channel.manager.start(pairing: pairing, name: "Usage fixture")
        defer { channel.manager.stop() }
        for _ in 0..<100 where channel.manager.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        let peer = MachLinkChannel()
        peer.pairing = pairing
        peer.endpoint = .hostPort(host: "127.0.0.1", port: channel.manager.port!)
        let snapshot = try await peer.requestUsageSnapshot(providers: ["fixture"], timeout: .seconds(2))
        precondition(snapshot.readings.first?.usedFraction == 0.15, "Peer route reads the module's Magpie snapshots")
        let filtered = try await peer.requestUsageSnapshot(providers: ["missing"], timeout: .seconds(2))
        precondition(filtered.readings.isEmpty)
        preferences.set(.aiUsageOtherMac, false)
        do {
            _ = try await peer.requestUsageSnapshot(providers: ["fixture"], timeout: .seconds(2))
            preconditionFailure("Disabled peer route answered")
        } catch {}
        preferences.set(.aiUsage, false)
        preferences.set(.machLink, false)
        for _ in 0..<30 { await Task.yield() }
        precondition(!module.isRunning && module.snapshots.isEmpty && !module.isLoading)
        precondition(!link.isRunning && link.channel.manager.port == nil)
        print("PASS: real HTTP, loading, empty, 503, gateway normalization and races, reset freshness, module peer route")
    }
}
