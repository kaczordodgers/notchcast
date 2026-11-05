import Foundation

@MainActor
final class LauncherAnswersModule: NotchcastModule {
    private(set) var isRunning = false
    private(set) var provider: NBPAnswerRateProvider?
    private let makeProvider: () -> NBPAnswerRateProvider
    private let clock: () -> Date
    private var table: NBPAnswerRates?
    private var attemptedDay: Date?
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
        attemptedDay = nil
    }

    func answer(for query: String) async -> LauncherCurrencyAnswer? {
        guard isRunning, let provider, let question = CurrencyAnswerQuery.parse(query) else { return nil }
        let operation = generation
        let now = clock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let day = calendar.startOfDay(for: now)
        if pending == nil, attemptedDay != day {
            attemptedDay = day
            pending = Task { try? await provider.rates(fetchedAt: now) }
        }
        if let pending {
            let fetched = await pending.value
            guard !Task.isCancelled, isRunning, generation == operation else { return nil }
            if attemptedDay == day {
                if let fetched { table = fetched }
                self.pending = nil
            }
        }
        guard !Task.isCancelled, isRunning, generation == operation, let table,
            let value = table.rates.convert(question.amount, from: question.source, to: question.target)
        else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return LauncherCurrencyAnswer(query: question, converted: value, effectiveDate: table.effectiveDate,
                                      isStale: table.effectiveDate != formatter.string(from: now))
    }
}
