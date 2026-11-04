import Foundation

@MainActor
final class AgentPricingModule {
    private(set) var isRunning = false
    private(set) var report: AgentPricingEngine.Report?
    private var budgetDay: Date?
    private let engine: AgentPricingEngine

    init(engine: AgentPricingEngine) {
        self.engine = engine
    }

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
        report = nil
        budgetDay = nil
    }

    // Call with the complete snapshot, never append cumulative session counters.
    func update(_ usage: [some AgentTokenUsage], calendar: Calendar, now: Date,
                dailyBudgetUSD: Decimal?, budgetReached: (Decimal) -> Void) {
        guard isRunning else { return }
        let next = engine.report(usage, calendar: calendar)
        report = next
        let day = calendar.startOfDay(for: now)
        guard let budget = dailyBudgetUSD, !budget.isNaN, budget > 0,
              let today = next.days[day], today.costUSD >= budget, budgetDay != day else { return }
        budgetDay = day
        budgetReached(today.costUSD)
    }
}
