import Foundation

struct AgentPricingEngine: Sendable {
    struct Price: Codable, Sendable {
        let id: String
        let input: Decimal
        let output: Decimal
        let cacheRead: Decimal
        let cacheWrite: Decimal?
    }

    struct Table: Decodable, Sendable {
        struct Provider: Decodable, Sendable {
            let models: [Price]
        }

        let updated: String
        let claude: Provider
        let codex: Provider
    }

    struct Totals: Sendable {
        var costUSD: Decimal = 0
        var unpricedCount = 0

        var isComplete: Bool { unpricedCount == 0 }

        mutating func add(_ cost: Decimal?) {
            if let cost { costUSD += cost } else { unpricedCount += 1 }
        }
    }

    struct Report: Sendable {
        var total = Totals()
        var sessions: [String: Totals] = [:]
        var projects: [String: Totals] = [:]
        var days: [Date: Totals] = [:]
    }

    let table: Table

    func cost(_ usage: some AgentTokenUsage) -> Decimal? {
        let counts = [usage.inputTokens, usage.outputTokens, usage.cacheReadTokens, usage.cacheWriteTokens]
        guard counts.allSatisfy({ $0 >= 0 }) else { return nil }
        let models = table.claude.models + table.codex.models
        let modelID = usage.modelID.replacingOccurrences(of: "-([0-9]{8}|[0-9]{4}-[0-9]{2}-[0-9]{2})$", with: "", options: .regularExpression)
        guard let price = models.first(where: { $0.id == usage.modelID })
            ?? models.first(where: { $0.id == modelID }) else {
            guard let reported = usage.reportedCostUSD, !reported.isNaN, reported >= 0 else { return nil }
            return reported
        }
        return (Decimal(usage.inputTokens) * price.input
            + Decimal(usage.outputTokens) * price.output
            + Decimal(usage.cacheReadTokens) * price.cacheRead
            + Decimal(usage.cacheWriteTokens) * (price.cacheWrite ?? price.input)) / 1_000_000
    }

    func report(_ usage: [some AgentTokenUsage], calendar: Calendar) -> Report {
        var result = Report()
        for entry in usage {
            let cost = cost(entry)
            result.total.add(cost)
            result.sessions[entry.sessionID, default: Totals()].add(cost)
            result.projects[entry.projectID, default: Totals()].add(cost)
            result.days[calendar.startOfDay(for: entry.timestamp), default: Totals()].add(cost)
        }
        return result
    }
}
