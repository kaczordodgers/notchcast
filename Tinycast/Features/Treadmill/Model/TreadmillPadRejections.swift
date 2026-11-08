import Foundation

struct TreadmillPadRejections: Sendable {
    private static let discoveryErrorLimit = 3
    private var rejected = Set<UUID>()
    private var discoveryErrors = 0

    func allows(_ id: UUID) -> Bool { !rejected.contains(id) }

    /// Returns whether the pad has now failed discovery often enough to be rejected.
    mutating func discoveryFailed() -> Bool {
        discoveryErrors += 1
        return discoveryErrors >= Self.discoveryErrorLimit
    }

    mutating func ready() { discoveryErrors = 0 }

    mutating func reject(_ id: UUID) {
        discoveryErrors = 0
        rejected.insert(id)
    }

    mutating func stop() { self = Self() }
}
