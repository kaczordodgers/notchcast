// notchcast-sources: Tinycast/Features/AIUsage/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/Service/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Model/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/Service/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/OtherMac/*.swift
// notchcast-sources: Tinycast/Features/AIUsage/AIUsageModule.swift
// notchcast-sources: Tinycast/Features/AIUsage/AIUsageLinkModule.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Model/*.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Service/BlockedDialogWindows.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/*.swift
// notchcast-sources: Tinycast/Features/MachLink/Service/*.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation
import Network

@main
struct AIUsageWiringTest {
    @MainActor static func main() async throws {
        let suite = "ai-usage-wire-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = Data("""
        {"displayName":"Fixture","usageLimits":{"checkedAt":"2026-11-04T00:00:00Z",
        "windows":[{"id":"weekly","label":"Weekly","usedPercent":42}]}}
        """.utf8)
        try cache.write(to: directory.appendingPathComponent("fixture.json"))
        let provider = AIUsageProvider(cacheDirectory: directory)
        let channel = MachLinkUsagePeerChannel()
        let module = AIUsageModule(provider: provider, preferences: preferences, channel: channel)
        let link = AIUsageLinkModule(preferences: preferences, provider: provider, defaults: defaults)
        link.listenerRoute = { request in
            guard request.method == "fixture-route" else { return nil }
            return try MachLinkMessage(id: request.id, method: request.method, value: true)
        }
        let routed = try await link.respond(to: MachLinkMessage(method: "fixture-route", value: true))
        let accepted = try routed.value(as: Bool.self)
        precondition(accepted)
        var missingNotices: [String] = []
        preferences.aiUsageCachePath = directory.path
        let defaultCacheModule = AIUsageModule(preferences: preferences, post: { missingNotices.append($0) })
        defaultCacheModule.start()
        try await defaultCacheModule.refresh()
        precondition(missingNotices.isEmpty)
        precondition(defaultCacheModule.snapshots.first?.windows.first?.used == 42)
        defaultCacheModule.stop()
        let controller = NotchcastModuleController([
            .init(requires: [.aiUsage], module: module),
            .init(requires: [.machLink], module: link),
        ], preferences: preferences)
        controller.run()
        try await module.refresh()
        precondition(!module.isRunning && module.snapshots.isEmpty)
        preferences.set(.aiUsage, true)
        for _ in 0..<30 { await Task.yield() }
        precondition(module.isRunning && module.snapshots.isEmpty)
        try await module.refresh()
        precondition(module.snapshots.first?.windows.first?.used == 42)
        preferences.set(.aiUsageOtherMac, true)
        preferences.set(.machLink, true)
        for _ in 0..<30 { await Task.yield() }
        try await module.refresh()
        precondition(module.peerStatus == String(localized: "Not connected"))
        let pairing = try MachLinkPairing.create()
        let server = MachLinkManager()
        try server.start(pairing: pairing, name: "Usage fixture") { request in
            try await MachLinkUsagePeerChannel.response(to: request, provider: provider)
        }
        defer { server.stop() }
        for _ in 0..<100 where server.port == nil { try await Task.sleep(for: .milliseconds(20)) }
        channel.pairing = pairing
        channel.endpoint = .hostPort(host: "127.0.0.1", port: server.port!)
        let snapshot = try await channel.requestUsageSnapshot(providers: ["fixture"], timeout: .seconds(5))
        precondition(snapshot.readings.first?.usedFraction == 0.42)
        precondition(snapshot.readings.first?.isStale == true)
        let connected = AIUsageModule(provider: provider, preferences: preferences, channel: channel)
        connected.start()
        try await connected.refresh()
        precondition(connected.otherMac.peerStatus == .available)
        preferences.set(.aiUsageOtherMac, false)
        for _ in 0..<30 { await Task.yield() }
        precondition(connected.otherMac.peerStatus == .disabled)
        connected.stop()
        connected.start()
        connected.stop()
        connected.start()
        preferences.set(.aiUsageOtherMac, true)
        for _ in 0..<30 { await Task.yield() }
        try await connected.refresh()
        precondition(connected.otherMac.peerStatus == .available)
        connected.stop()
        preferences.set(.aiUsage, false)
        preferences.set(.machLink, false)
        for _ in 0..<30 { await Task.yield() }
        precondition(!module.isRunning && module.snapshots.isEmpty && !link.isRunning)
        precondition(link.channel.manager.port == nil)
        print("PASS: default off, lazy fixture read, not connected, peer loopback, switches stop modules")
    }
}
