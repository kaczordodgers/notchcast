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
// notchcast-sources: Tinycast/Features/Todo/Model/*.swift Tinycast/Features/Todo/Service/TodoStore*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoIsland*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoLinkCoordinator.swift
// notchcast-sources: Tinycast/Features/Todo/TodoModule.swift Tinycast/Features/Todo/TodoLinkWiring.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Service/RemoteFan*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/RemoteFanPeer.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Store/FanControl+Completion.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/FanOwnershipJournal.swift
import Foundation
import Network

@MainActor final class MonitorModule {
    let fans = FanControl(runner: { _ in })
}
struct RootHelperClient {
    enum Failure: Error { case executionFailed(Int) }
    func run(_ command: RootContract.Command) async throws {}
}
struct SMCClient {
    init?() {}
    func value(_ key: String) -> Double? {
        ["FNum": 1, "F0Ac": 3000, "F0Tg": 6000, "F0Mn": 1000, "F0Mx": 6000][key]
    }
}

@main
struct MachLinkRoutesTest {
    @MainActor static func main() async throws {
        let suite = "mach-link-routes-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        for feature: NotchcastFeature in [.aiUsage, .aiUsageOtherMac, .machLink, .tasks, .tasksSync, .systemMonitor,
                                          .fanControl] {
            preferences.set(feature, true)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pairing = try MachLinkPairing.create()
        let server = MachLinkChannel()
        _ = AIUsageModule(provider: AIUsageProvider(cacheDirectory: directory), preferences: preferences, channel: server)
        let tasks = TodoLinkCoordinator.live(channel: server, preferences: preferences)
        let store = try await TodoStore.open(directory: directory.appending(path: "tasks"))
        defer { try? store.close() }
        try store.perform(.addTask(.init(id: UUID().uuidString, title: "Served over Mac Link")))
        tasks.opened(store)
        tasks.start()
        let monitor = MonitorModule()
        monitor.registerRemoteFanRoute(on: server, preferences: preferences)
        var wrongIDServed = false
        server.manager.register("wrong-id") { request in
            wrongIDServed = true
            return try MachLinkMessage(method: request.method, value: true)
        }
        var replaced: MachLinkChannel?
        server.manager.register("replace-pairing") { request in
            replaced?.pairing = try MachLinkPairing.create()
            return try MachLinkMessage(id: request.id, method: request.method, value: true)
        }
        try server.manager.start(pairing: pairing, name: "Routes fixture")
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

        let packet = TodoLinkPacket(clock: TodoVectorClock(), envelopes: [], hasMore: false)
        let synced = try await client.request(packet, method: "todo-sync", as: TodoLinkPacket.self)
        precondition(!synced.envelopes.isEmpty)
        print("PASS todo-sync registered from the Todo folder is served")

        let fans = try await client.request(RemoteFanRequest.max, method: "mbp-fans", as: RemoteFanReport.self)
        precondition(fans.mode == .max && fans.fans.count == 1)
        print("PASS mbp-fans registered from the MachMBPFans folder is served")

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
        tasks.stop()
        do {
            _ = try await client.request(packet, method: "todo-sync", as: TodoLinkPacket.self)
            fatalError("todo-sync served by a stopped coordinator")
        } catch { print("PASS todo-sync refused once its coordinator stops") }
        preferences.set(.fanControl, false)
        do {
            _ = try await client.request(RemoteFanRequest.max, method: "mbp-fans", as: RemoteFanReport.self)
            fatalError("mbp-fans served with fan control off")
        } catch { print("PASS mbp-fans refused with fan control off") }

        do {
            _ = try await client.request(true, method: "unregistered", timeout: .seconds(1), as: Bool.self)
            fatalError("Unregistered method answered")
        } catch { print("PASS unregistered method refused") }

        do {
            _ = try await client.request(true, method: "wrong-id", timeout: .seconds(1), as: Bool.self)
            fatalError("Reply with another request's id accepted")
        } catch {
            precondition(wrongIDServed)
            print("PASS route reply with a different id refused")
        }

        replaced = client
        do {
            _ = try await client.request(true, method: "replace-pairing", as: Bool.self)
            fatalError("Reply from a replaced pairing accepted")
        } catch MachLinkMessage.Failure.disconnected { print("PASS reply from a replaced pairing discarded") }
    }
}
