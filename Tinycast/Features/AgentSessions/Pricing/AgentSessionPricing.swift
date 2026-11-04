import Foundation

enum AgentSessionPricing {
    private static let engine = try? AgentPricingCatalog.bundled()
    private struct Usage: AgentTokenUsage {
        let sessionID: String
        let projectID: String
        let timestamp: Date
        let modelID: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
        let reportedCostUSD: Decimal?
    }

    static func report(_ sessions: [AgentSession], calendar: Calendar) -> AgentPricingEngine.Report? {
        guard let engine else { return nil }
        let usage = sessions.flatMap { session in
            session.usage.map { entry in
                Usage(sessionID: session.id, projectID: session.project ?? session.id,
                      timestamp: entry.day, modelID: entry.model ?? session.model ?? "",
                      inputTokens: Int(clamping: entry.tokens.input),
                      outputTokens: Int(clamping: entry.tokens.output),
                      cacheReadTokens: Int(clamping: entry.tokens.cacheRead),
                      cacheWriteTokens: Int(clamping: entry.tokens.cacheWrite),
                      reportedCostUSD: entry.reportedCost.map { Decimal($0) })
            }
        }
        return engine.report(usage, calendar: calendar)
    }
}
