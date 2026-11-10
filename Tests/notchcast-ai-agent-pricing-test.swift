// notchcast-sources: Tinycast/Features/AgentSessions/Pricing/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/Model/AgentSession.swift
import Foundation

private struct Usage: AgentTokenUsage {
    var sessionID = "session"
    var projectID = "project"
    var timestamp = Date(timeIntervalSince1970: 0)
    var modelID = "gpt-4.1"
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var reportedCostUSD: Decimal?
}

@main
struct PricingTests {
    @MainActor
    static func main() throws {
        let engine = try AgentPricingCatalog.bundled()
        for price in engine.table.claude.models + engine.table.codex.models {
            let cost = engine.cost(Usage(modelID: price.id, inputTokens: 1_000_000))
            precondition((cost ?? 0) > 0, "Bundled model \(price.id) must price a 1M-token usage")
        }
        var usage = Usage(inputTokens: 1_000_000, outputTokens: 1_000_000)
        precondition(engine.cost(usage) == 10)
        usage.modelID = "gpt-4.1-20260102"
        precondition(engine.cost(usage) == 10, "Dated model identifiers retain their base price")
        usage.modelID = "gpt-4.1-2025-04-14"
        precondition(engine.cost(usage) == 10, "Dashed dates retain their base price")
        usage.modelID = "gpt-4.1"
        usage.cacheReadTokens = 1_000_000
        usage.cacheWriteTokens = 1_000_000
        precondition(engine.cost(usage) == Decimal(string: "12.5"))
        usage.modelID = "claude-sonnet-4-5"
        let price = engine.table.claude.models.first { $0.id == usage.modelID }!
        precondition(engine.cost(usage) == price.input + price.output + price.cacheRead + price.cacheWrite!)
        usage.modelID = "unknown"
        precondition(engine.cost(usage) == nil)
        usage.reportedCostUSD = Decimal(string: "1.25")
        precondition(engine.cost(usage) == Decimal(string: "1.25"))
        usage.reportedCostUSD = -1
        precondition(engine.cost(usage) == nil)
        usage.modelID = "gpt-4.1"
        usage.inputTokens = -1
        precondition(engine.cost(usage) == nil)
        precondition(AgentPricingEngine.roundedUSD(Decimal(string: "1.005")!) == Decimal(string: "1.01"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let first = Usage(inputTokens: 1_000)
        let second = Usage(sessionID: "second", projectID: "other",
                           timestamp: Date(timeIntervalSince1970: 86_400), inputTokens: 2_000)
        let unknown = Usage(modelID: "unpriced")
        let report = engine.report([first, second, unknown], calendar: calendar)
        precondition(report.total.costUSD == Decimal(string: "0.006"))
        precondition(report.total.unpricedCount == 1 && !report.total.isComplete)
        precondition(report.sessions["session"]?.costUSD == Decimal(string: "0.002"))
        precondition(report.projects["other"]?.costUSD == Decimal(string: "0.004"))
        precondition(report.days.count == 2)
        precondition(AgentPricingEngine.roundedUSD(report.total.costUSD) == Decimal(string: "0.01"))
        print("Agent pricing checks passed")
    }
}
