import Foundation

protocol AgentTokenUsage: Sendable {
    var sessionID: String { get }
    var projectID: String { get }
    var timestamp: Date { get }
    var modelID: String { get }
    // Input excludes cache reads and writes; adapters normalize provider totals before pricing.
    var inputTokens: Int { get }
    var outputTokens: Int { get }
    var cacheReadTokens: Int { get }
    var cacheWriteTokens: Int { get }
    var reportedCostUSD: Decimal? { get }
}
