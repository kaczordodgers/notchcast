// notchcast-sources: Tinycast/Features/Answers/Model/*.swift
// notchcast-sources: Tinycast/Features/Answers/Service/*.swift
// notchcast-sources: Tinycast/Features/Answers/LauncherAnswersModule.swift
// notchcast-sources: Tinycast/Features/Calculator/Model/*.swift
// notchcast-kit: core
import Foundation
import Synchronization

@main
struct AnswersEngineTest {
    @MainActor
    static func main() async {
        for text in ["100 usd", "100 usd to eur", "100 usd in pln", "12,5 eur", "12.5 EUR"] {
            precondition(CurrencyAnswerQuery.parse(text) != nil, text)
        }
        for text in ["Safari", "2+2", "100 btc", "100 usd to kg", "1,2.3 eur", "nan eur",
                     "1e3 usd", "100 usd extra"] {
            precondition(CurrencyAnswerQuery.parse(text) == nil, text)
        }
        precondition(CurrencyAnswerQuery.parse("1,000 usd")?.amount == 1000)
        precondition(CurrencyAnswerQuery.parse("12,5 eur")?.amount == 12.5)
        let small = LauncherCurrencyAnswer(query: CurrencyAnswerQuery.parse("1 krw to usd")!,
                                          converted: 0.000725, effectiveDate: "2026-11-03", isStale: false)
        precondition(small.formattedValue(locale: Locale(identifier: "en_US")) == "0.000725 USD")
        let data = Data(#"[{"effectiveDate":"2026-11-03","rates":[{"code":"EUR","mid":4.25},{"code":"USD","mid":4}]}]"#.utf8)
        var now = Date(timeIntervalSince1970: 1_793_750_400)
        let calls = Mutex(0)
        let module = LauncherAnswersModule(provider: {
            NBPAnswerRateProvider { _ in
                let count = calls.withLock { value in value += 1; return value }
                return (data, count == 1 ? 200 : 503)
            }
        }, clock: { now })
        let disabled = await module.answer(for: "100 usd")
        precondition(disabled == nil)
        module.start()
        let first = await module.answer(for: "100 usd to eur")
        precondition(abs(first!.converted - 400 / 4.25) < 1e-10)
        precondition(first!.formattedValue(locale: Locale(identifier: "pl_PL")).contains(","))
        precondition(first!.formattedValue(locale: Locale(identifier: "en_US")).contains("."))
        precondition(first?.isStale == false)
        _ = await module.answer(for: "100 usd")
        precondition(calls.withLock { $0 } == 1)
        now += 86_400
        let next = await module.answer(for: "12,5 eur")
        precondition(next?.converted == 53.125)
        precondition(next?.isStale == true)
        precondition(calls.withLock { $0 } == 2)
        now += 299
        _ = await module.answer(for: "100 usd")
        precondition(calls.withLock { $0 } == 2)
        now += 1
        _ = await module.answer(for: "100 usd")
        precondition(calls.withLock { $0 } == 3)
        _ = await module.answer(for: "100 usd")
        precondition(calls.withLock { $0 } == 3)
        module.stop()
        let stopped = await module.answer(for: "100 usd")
        precondition(stopped == nil)
        let offline = LauncherAnswersModule(provider: {
            NBPAnswerRateProvider { _ in throw URLError(.notConnectedToInternet) }
        })
        offline.start()
        let unavailable = await offline.answer(for: "100 usd")
        precondition(unavailable == nil)
        let gate = FetchGate()
        let concurrent = LauncherAnswersModule(provider: {
            NBPAnswerRateProvider { _ in await gate.fetch() }
        }, clock: { now })
        concurrent.start()
        let one = Task { await concurrent.answer(for: "100 usd") }
        let two = Task { await concurrent.answer(for: "100 eur") }
        while gate.count < 1 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        precondition(gate.count == 1)
        gate.finish(data)
        let firstShared = await one.value
        let secondShared = await two.value
        precondition(firstShared != nil && secondShared != nil)
        now += 3600
        let old = Task { await concurrent.answer(for: "100 usd") }
        while gate.count < 2 { await Task.yield() }
        concurrent.stop()
        concurrent.start()
        let fresh = Task { await concurrent.answer(for: "100 eur") }
        while gate.count < 3 { await Task.yield() }
        gate.finish(data)
        let stoppedResult = await old.value
        precondition(stoppedResult == nil)
        gate.finish(data)
        let freshResult = await fresh.value
        precondition(freshResult != nil)
        for status in [200, 503] {
            let cancellationGate = FetchGate()
            let cancellationModule = LauncherAnswersModule(provider: {
                NBPAnswerRateProvider { _ in await cancellationGate.fetch() }
            }, clock: { now })
            cancellationModule.start()
            let caller = Task { await cancellationModule.answer(for: "1 usd") }
            while cancellationGate.count < 1 { await Task.yield() }
            caller.cancel()
            cancellationGate.finish(data, status: status)
            let cancelledResult = await caller.value
            precondition(cancelledResult == nil)
            let cached = await cancellationModule.answer(for: "2 usd")
            precondition((cached != nil) == (status == 200))
            precondition(cancellationGate.count == 1)
            now += status == 200 ? 3600 : 300
            let retry = Task { await cancellationModule.answer(for: "3 usd") }
            for _ in 0..<1000 { await Task.yield() }
            precondition(cancellationGate.count == 2, "Cancelled caller must finalize shared refresh")
            cancellationGate.finish(data)
            let retryResult = await retry.value
            precondition(retryResult != nil)
        }
        print("PASS grouping, small values, retry at 300s, shared fetch, stop/restart, cancelled success/failure")
    }
}

final class FetchGate: Sendable {
    private let state = Mutex((count: 0, waiters: [CheckedContinuation<(Data, Int), Never>]()))
    var count: Int { state.withLock { $0.count } }

    func fetch() async -> (Data, Int) {
        await withCheckedContinuation { continuation in
            state.withLock { $0.count += 1; $0.waiters.append(continuation) }
        }
    }

    func finish(_ data: Data, status: Int = 200) {
        let waiter = state.withLock { $0.waiters.removeFirst() }
        waiter.resume(returning: (data, status))
    }
}
