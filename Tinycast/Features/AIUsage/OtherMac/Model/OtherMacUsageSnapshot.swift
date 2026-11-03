import Foundation

nonisolated struct OtherMacUsageSnapshot: Codable, Sendable, Equatable {
    var readings: [Reading]

    struct Reading: Codable, Sendable, Equatable {
        var providerID: String
        // The adapter supplies a stable, opaque account/plan identity, never a credential.
        var planID: String
        var windowID: String
        var usedFraction: Double
        var observedAt: Date
    }
}
