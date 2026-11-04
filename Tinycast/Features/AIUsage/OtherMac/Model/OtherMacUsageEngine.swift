import Foundation

nonisolated enum OtherMacUsageEngine {
    struct Reading: Sendable, Equatable {
        var value: OtherMacUsageSnapshot.Reading
        var isStale: Bool
    }

    private struct Key: Hashable {
        var provider: String
        var plan: String
        var window: String
    }

    static func merge(
        local: OtherMacUsageSnapshot?, peer: OtherMacUsageSnapshot?,
        now: Date, maximumAge: TimeInterval, peerFailed: Bool = false, localFailed: Bool = false
    ) -> [Reading] {
        var result: [Key: Reading] = [:]
        for (snapshot, failed) in [(local, localFailed), (peer, peerFailed)] {
            for value in snapshot?.readings ?? [] {
                guard !value.providerID.isEmpty, !value.planID.isEmpty, !value.windowID.isEmpty,
                      value.usedFraction.isFinite, (0...1).contains(value.usedFraction) else { continue }
                let age = now.timeIntervalSince(value.observedAt)
                let reading = Reading(value: value,
                    isStale: value.isStale == true || failed || age < 0 || age >= maximumAge)
                let key = Key(provider: value.providerID, plan: value.planID, window: value.windowID)
                if let existing = result[key] {
                    if existing.isStale != reading.isStale {
                        guard existing.isStale else { continue }
                    } else {
                        guard value.observedAt > existing.value.observedAt else { continue }
                    }
                }
                result[key] = reading
            }
        }
        return result.values.sorted {
            ($0.value.providerID, $0.value.planID, $0.value.windowID)
                < ($1.value.providerID, $1.value.planID, $1.value.windowID)
        }
    }
}
