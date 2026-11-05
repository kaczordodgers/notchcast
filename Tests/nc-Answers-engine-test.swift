// notchcast-sources: Tinycast/Features/Launcher/Answers/Model/*.swift
// notchcast-sources: Tinycast/Features/Launcher/Answers/Service/*.swift
// notchcast-sources: Tinycast/Features/Launcher/Answers/LauncherAnswersModule.swift
// notchcast-sources: Tinycast/Features/Calculator/Model/*.swift
import Foundation
import Synchronization

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

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
        let data = Data(#"[{"effectiveDate":"2026-11-03","rates":[{"code":"EUR","mid":4.25},{"code":"USD","mid":4}]}]"#.utf8)
        var now = Date(timeIntervalSince1970: 1_793_664_000)
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
        _ = await module.answer(for: "100 usd")
        precondition(calls.withLock { $0 } == 1)
        now += 86_400
        let next = await module.answer(for: "12,5 eur")
        precondition(next?.converted == 53.125)
        precondition(next?.isStale == true)
        precondition(calls.withLock { $0 } == 2)
        _ = await module.answer(for: "100 usd")
        precondition(calls.withLock { $0 } == 2)
        module.stop()
        let stopped = await module.answer(for: "100 usd")
        precondition(stopped == nil)
        let offline = LauncherAnswersModule(provider: {
            NBPAnswerRateProvider { _ in throw URLError(.notConnectedToInternet) }
        })
        offline.start()
        let unavailable = await offline.answer(for: "100 usd")
        precondition(unavailable == nil)
        print("PASS parser, conversion, locales, rollover, offline, switch-off")
    }
}
