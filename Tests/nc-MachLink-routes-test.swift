// notchcast-sources: Tinycast/Features/MachLink/Model/*.swift Tinycast/Features/MachLink/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/AIUsage/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/Service/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Service/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/AIUsageModule.swift
import Foundation
import Network

@main
struct MachLinkRoutesTest {
    @MainActor static func main() async throws {
        let suite = "mach-link-routes-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.aiUsage, true)
        preferences.set(.aiUsageOtherMac, true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pairing = try MachLinkPairing.create()
        let server = MachLinkChannel()
        _ = AIUsageModule(provider: AIUsageProvider(cacheDirectory: directory), preferences: preferences, channel: server)
        var replaced: MachLinkChannel?
        server.manager.register("replace-pairing") { request in
            replaced?.pairing = try MachLinkPairing.create()
            return try MachLinkMessage(id: request.id, method: request.method, value: true)
        }
        try server.manager.start(pairing: pairing, name: "Routes fixture") { request in
            try MachLinkMessage(id: request.id, method: request.method, value: "fallback")
        }
        defer { server.manager.stop() }
        for _ in 0..<100 where server.manager.port == nil { try await Task.sleep(for: .milliseconds(20)) }
        guard let port = server.manager.port else { fatalError("Listener did not start") }

        let client = MachLinkChannel()
        do {
            _ = try await client.request(true, method: "link-health", as: Bool.self)
            fatalError("Unpaired channel sent a request")
        } catch MachLinkMessage.Failure.disconnected { print("PASS no pairing, no peer") }
        client.pairing = pairing
        precondition(client.peer == nil)
        do {
            _ = try await client.request(true, method: "link-health", as: Bool.self)
            fatalError("Request sent with no advertised peer")
        } catch MachLinkMessage.Failure.disconnected { print("PASS no advertised peer, no request") }

        client.endpoint = .hostPort(host: "127.0.0.1", port: port)
        let snapshot = try await client.requestUsageSnapshot(providers: ["fixture"], timeout: .seconds(5))
        precondition(snapshot.readings.isEmpty)
        print("PASS route registered from the AI Usage folder is served")

        let stranger = MachLinkChannel()
        stranger.pairing = try .create()
        stranger.endpoint = client.endpoint
        do {
            _ = try await stranger.request(Set(["fixture"]), method: "ai-usage", timeout: .seconds(1),
                as: OtherMacUsageSnapshot.self)
            fatalError("Peer from another pairing was served")
        } catch { print("PASS unpaired peer refused") }

        preferences.set(.aiUsageOtherMac, false)
        do {
            _ = try await client.requestUsageSnapshot(providers: ["fixture"], timeout: .seconds(5))
            fatalError("Route served with its feature off")
        } catch { print("PASS feature switch still gates its route") }

        let fallback = try await client.request(true, method: "unregistered", as: String.self)
        precondition(fallback == "fallback")
        print("PASS unregistered method reaches the fallback handler")

        replaced = client
        do {
            _ = try await client.request(true, method: "replace-pairing", as: Bool.self)
            fatalError("Reply from a replaced pairing accepted")
        } catch MachLinkMessage.Failure.disconnected { print("PASS reply from a replaced pairing discarded") }
    }
}
