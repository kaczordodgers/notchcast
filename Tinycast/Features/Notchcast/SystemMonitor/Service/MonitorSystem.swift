import Foundation

/// The Mac as the module sees it, so a harness can drive the module without touching hardware.
struct MonitorSystem: Sendable {
    /// `detail` adds what only the page shows: volumes, network counters and the process walk.
    var read: @Sendable (_ detail: Bool, _ previous: [Int32: UInt64]) async -> MonitorReading
    var eject: @Sendable (_ path: String) async -> MonitorEjectResult
    var sleep: @Sendable (Duration) async throws -> Void
    var processorCount: Int
}
