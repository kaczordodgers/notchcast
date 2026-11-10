// notchcast-sources: Tinycast/Features/Answers/Model/*.swift
// notchcast-sources: Tinycast/Features/Answers/Service/*.swift
// notchcast-sources: Tinycast/Features/Calculator/Model/*.swift
import Foundation

@main
struct LauncherAnswersTest {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        let data = Data(#"[{"effectiveDate":"2026-11-03","rates":[{"code":"EUR","mid":4.25},{"code":"USD","mid":4}]}]"#.utf8)
        let provider = NBPAnswerRateProvider { request in
            precondition(request.url?.host == "api.nbp.pl" && request.timeoutInterval == 10)
            return (data, 200)
        }
        let table = try await provider.rates(fetchedAt: now)
        precondition(table.effectiveDate == "2026-11-03" && table.rates.fetchedAt == now)
        precondition(table.rates.convert(100, from: "EUR", to: "PLN") == 425)
        precondition(table.rates.convert(425, from: "PLN", to: "EUR") == 100)
        precondition(table.rates.convert(100, from: "EUR", to: "USD") == 106.25)
        precondition(table.rates.convert(1, from: "BTC", to: "PLN") == nil)
        for body in ["[]", "{}", #"[{"effectiveDate":"2026-02-30","rates":[{"code":"EUR","mid":4}]}]"#,
                     #"[{"effectiveDate":"2026-11-03","rates":[{"code":"EUR","mid":0}]}]"#,
                     #"[{"effectiveDate":"2026-11-03","rates":[{"code":"EUR","mid":4},{"code":"EUR","mid":5}]}]"#] {
            do {
                _ = try NBPAnswerRates.decode(Data(body.utf8), fetchedAt: now)
                preconditionFailure("Invalid table accepted")
            } catch {}
        }
        do {
            _ = try await NBPAnswerRateProvider { _ in (data, 503) }.rates(fetchedAt: now)
            preconditionFailure("HTTP failure accepted")
        } catch {}
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for query in ["2+2", "255 to hex", "10 km to m", "100 EUR to PLN", "tomorrow", "now to unix"] {
            precondition(CalcEngine.evaluate(query, now: now, calendar: calendar, rates: table.rates) != nil, query)
        }
        let polish = CalcNumberFormat(decimalSeparator: ",", groupingSeparator: "\u{00A0}")!
        precondition(CalcEngine.evaluate("1,5+2", now: now, calendar: calendar, format: polish) != nil)
        precondition(CalcEngine.evaluate("Safari", now: now, calendar: calendar) == nil)
        print("Verified launcher-answers: NBP cross-rates, invalid tables, HTTP errors; upstream calculator and locale")
    }
}
