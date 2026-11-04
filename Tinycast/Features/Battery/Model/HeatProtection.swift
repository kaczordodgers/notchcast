import Foundation

struct HeatProtection: Sendable, Equatable, Codable {
    private(set) var lastHot: Date?

    mutating func paused(enabled: Bool, celsius: Double?, now: Date) -> Bool {
        guard enabled else { lastHot = nil; return false }
        if let celsius, celsius.isFinite, celsius >= 35 { lastHot = now }
        guard let lastHot else { return false }
        return now.timeIntervalSince(lastHot) < 300
    }
}
