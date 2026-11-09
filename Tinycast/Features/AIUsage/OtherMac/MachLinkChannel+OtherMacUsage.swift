import Foundation

extension MachLinkChannel: OtherMacUsagePeerChannel {
    func requestUsageSnapshot(providers: Set<String>, timeout: Duration) async throws -> OtherMacUsageSnapshot {
        try await request(providers, method: "ai-usage", timeout: min(timeout, .seconds(2)), as: OtherMacUsageSnapshot.self)
    }

    func registerUsageRoute(provider: AIUsageProvider?, preferences: NotchcastPreferences) {
        manager.register("ai-usage") { request in
            guard preferences.isOn(.aiUsage), preferences.isOn(.aiUsageOtherMac) else {
                throw MachLinkMessage.Failure.disconnected
            }
            let provider = provider ?? AIUsageProvider(cacheDirectory: AIUsageProvider.cacheDirectory(
                path: preferences.aiUsageCachePath, homeDirectory: FileManager.default.homeDirectoryForCurrentUser))
            let providers = try request.value(as: Set<String>.self)
            let source = AIUsageSnapshotAdapter()
            source.snapshots = await provider.refresh().filter { providers.contains($0.providerID) }
            let response = try MachLinkMessage(id: request.id, method: request.method, value: await source.localSnapshot())
            try Task.checkCancellation()
            guard preferences.isOn(.aiUsage), preferences.isOn(.aiUsageOtherMac) else {
                throw MachLinkMessage.Failure.disconnected
            }
            return response
        }
    }
}
