import Foundation

@MainActor
final class AIUsageSnapshotAdapter: OtherMacUsageSnapshotSource {
    var snapshots: [AIUsageSnapshot] = []

    func localSnapshot() async throws -> OtherMacUsageSnapshot {
        OtherMacUsageSnapshot(readings: snapshots.flatMap { snapshot in
            guard let observedAt = snapshot.checkedAt, let plan = snapshot.plan else {
                return [OtherMacUsageSnapshot.Reading]()
            }
            return snapshot.windows.compactMap { window in
                guard window.limit > 0 else { return nil }
                return OtherMacUsageSnapshot.Reading(
                    providerID: snapshot.providerID, planID: plan, windowID: window.id,
                    usedFraction: min(1, window.used / window.limit), observedAt: observedAt,
                    isStale: snapshot.status == .stale)
            }
        })
    }
}
