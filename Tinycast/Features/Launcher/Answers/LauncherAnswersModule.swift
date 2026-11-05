import Foundation

@MainActor
final class LauncherAnswersModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var provider: NBPAnswerRateProvider?
    private let makeProvider: () -> NBPAnswerRateProvider
    private let clock: () -> Date
    private var table: NBPAnswerRates?
    private var lastAttempt: Date?
    private var refreshFailed = false
    private var generation = UUID()
    private var pending: Task<NBPAnswerRates?, Never>?

    init(provider: @escaping () -> NBPAnswerRateProvider = { NBPAnswerRateProvider() },
         clock: @escaping () -> Date = Date.init) {
        makeProvider = provider
        self.clock = clock
    }

    func start() {
        isRunning = true
        provider = makeProvider()
    }

    func stop() {
        isRunning = false
        provider = nil
        generation = UUID()
        pending?.cancel()
        pending = nil
        lastAttempt = nil
        refreshFailed = false
    }

    func answer(for query: String) async -> LauncherCurrencyAnswer? {
        guard isRunning, let provider, let question = CurrencyAnswerQuery.parse(query) else { return nil }
        let operation = generation
        let now = clock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let age = lastAttempt.map { now.timeIntervalSince($0) } ?? .infinity
        let needsRefresh = lastAttempt == nil
            || (refreshFailed && age >= 300)
            || (!refreshFailed && table?.effectiveDate != formatter.string(from: now) && age >= 3600)
        if pending == nil, needsRefresh {
            lastAttempt = now
            pending = Task { try? await provider.rates(fetchedAt: now) }
        }
        if let pending {
            let fetched = await pending.value
            guard isRunning, generation == operation else { return nil }
            if let fetched { table = fetched }
            refreshFailed = fetched == nil
            self.pending = nil
        }
        guard !Task.isCancelled, isRunning, generation == operation, let table,
            let value = table.rates.convert(question.amount, from: question.source, to: question.target)
        else { return nil }
        return LauncherCurrencyAnswer(query: question, converted: value, effectiveDate: table.effectiveDate,
                                      isStale: refreshFailed && table.effectiveDate < formatter.string(from: now))
    }
}
