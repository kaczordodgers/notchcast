import Foundation

nonisolated struct OtherMacUsageSnapshot: Sendable, Equatable {
    var readings: [Reading]

    struct Reading: Sendable, Equatable {
        var providerID: String
        // The adapter supplies a stable, opaque account/plan identity, never a credential.
        var planID: String
        var windowID: String
        var usedFraction: Double
        var observedAt: Date
    }
}
