# Launcher currency answers

The hidden `launcherAnswers` module exposes `answer(for:)` for currency queries: `100 usd`, `100 usd to eur`, `100 usd in pln`, and `12,5 eur`. A missing target means PLN. Currency codes are case insensitive; both decimal separators work. Unknown currencies and noncurrency queries return nil without fetching.

NBP table A supplies mid rates; upstream `CurrencyRates` performs cross conversion through PLN. The module keeps one table in memory and attempts one fetch per Warsaw calendar day, including after a failed fetch. Concurrent callers share the pending fetch. A failed refresh retains the previous table and its effective date, with `isStale` marking an older table. No disk cache is written. Stopping cancels owned work and prevents late results from being returned; restarting permits a fresh attempt.

`LauncherCurrencyAnswer.formattedValue(locale:)` uses the caller's locale. The engine adds no localized prose. Crypto, units, dates, and time zones are outside this module; upstream's calculator remains responsible for its existing answers.

The switch stays hidden: `LauncherScreen` synchronously calls `CalcMemo.evaluate` and routes calculator actions through its existing coordinator. An async answer needs state and refresh ownership beyond the permitted two one-line hooks. This change adds no view or upstream hook. The visible real-app proof gate therefore does not apply.
