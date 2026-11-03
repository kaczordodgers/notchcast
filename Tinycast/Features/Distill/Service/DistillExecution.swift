import Foundation

nonisolated struct DistillExecution: Sendable {
    // The download queue owns child processes and cancellation; Distill only supplies arguments.
    let spawn: @Sendable (_ tool: String, _ arguments: [String]) async throws -> String
}
