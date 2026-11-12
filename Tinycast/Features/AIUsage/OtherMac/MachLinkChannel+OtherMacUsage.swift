import Foundation

extension MachLinkChannel: OtherMacUsagePeerChannel {
    func requestUsageSnapshot(providers: Set<String>, timeout: Duration) async throws -> OtherMacUsageSnapshot {
        try await request(providers, method: MachLinkMethod.aiUsage.rawValue, timeout: min(timeout, .seconds(2)), as: OtherMacUsageSnapshot.self)
    }

    func registerUsageRoute(source: AIUsageSnapshotAdapter, preferences: NotchcastPreferences) {
        manager.register(MachLinkMethod.aiUsage.rawValue) { request in
            guard preferences.isEnabled(.aiUsageOtherMac) else { throw MachLinkMessage.Failure.disconnected }
            let providers = try request.value(as: Set<String>.self)
            let local = try await source.localSnapshot()
            let snapshot = OtherMacUsageSnapshot(readings: local.readings.filter { providers.contains($0.providerID) })
            let response = try MachLinkMessage(id: request.id, method: request.method, value: snapshot)
            try Task.checkCancellation()
            guard preferences.isEnabled(.aiUsageOtherMac) else { throw MachLinkMessage.Failure.disconnected }
            return response
        }
    }
}
