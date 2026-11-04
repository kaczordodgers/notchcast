import Foundation

nonisolated enum AIUsageParser {
    private struct Cache: Decodable {
        let displayName: String
        let usageLimits: Limits?
    }

    private struct Limits: Decodable {
        let checkedAt: String
        let windows: [Window]
        let resetCredits: AIUsageSnapshot.ResetCredits?

        private enum CodingKeys: String, CodingKey {
            case checkedAt, windows, resetCredits
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            checkedAt = try values.decode(String.self, forKey: .checkedAt)
            windows = try values.decode([Window].self, forKey: .windows)
            let credits = try? values.decode(AIUsageSnapshot.ResetCredits.self, forKey: .resetCredits)
            resetCredits = credits.flatMap { $0.availableCount >= 0 ? $0 : nil }
        }
    }

    private struct Window: Decodable {
        let id: String
        let label: String
        let usedPercent: Double
        let resetsAt: String?
        let windowDurationMins: Double?
    }

    static func parse(
        _ data: Data, providerID: String, now: Date, staleAfter: TimeInterval
    ) throws -> AIUsageSnapshot {
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        guard let limits = cache.usageLimits else {
            return AIUsageSnapshot(providerID: providerID, plan: cache.displayName,
                                   checkedAt: nil, status: .noData, windows: [])
        }
        let checkedAt = try date(limits.checkedAt)
        let windows = try limits.windows.map { window in
            guard window.usedPercent.isFinite, window.usedPercent >= 0,
                  window.windowDurationMins.map({ $0.isFinite && $0 > 0 }) ?? true else {
                throw CocoaError(.coderReadCorrupt)
            }
            return AIUsageSnapshot.Window(
                id: window.id, label: window.label, used: window.usedPercent, limit: 100,
                resetsAt: try window.resetsAt.map(date), durationMinutes: window.windowDurationMins
            )
        }
        let expired = windows.contains { $0.resetsAt.map { $0 <= now } ?? false }
        let stale = now.timeIntervalSince(checkedAt) >= max(0, staleAfter) || expired || checkedAt > now
        return AIUsageSnapshot(providerID: providerID, plan: cache.displayName,
                               checkedAt: checkedAt,
                               status: windows.isEmpty ? .noData : (stale ? .stale : .available),
                               windows: windows, resetCredits: limits.resetCredits)
    }

    private static func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { throw CocoaError(.coderReadCorrupt) }
        return date
    }
}
