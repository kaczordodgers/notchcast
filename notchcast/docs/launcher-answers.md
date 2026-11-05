# Launcher currency answers

The hidden `launcherAnswers` module exposes `answer(for:)` for currency queries: `100 usd`, `100 usd to eur`, `100 usd in pln`, and `12,5 eur`. A missing target means PLN. Currency codes are case insensitive; both decimal separators work. Unknown currencies and noncurrency queries return nil without fetching.

NBP table A supplies mid rates; upstream `CurrencyRates` performs cross conversion through PLN. Failed attempts retry after five minutes; successful attempts retry after one hour while the effective date is older than today in Warsaw. Concurrent callers share the pending fetch. `isStale` means the last refresh failed and an older table is being shown. No disk cache is written. Stopping cancels owned work and prevents late results from being returned; restarting permits a fresh attempt.

Valid English comma grouping takes precedence: `1,000 usd` means 1000. Otherwise a comma is decimal, so `12,5 eur` means 12.5; mixed decimal separators are rejected unless they form valid English grouping. Parsing calls upstream `CalcNumberFormat.canonical(_:)`. Output uses two decimal places for magnitudes at least one and three significant digits for smaller nonzero values.

`LauncherCurrencyAnswer.formattedValue(locale:)` uses the caller's locale. The engine adds no localized prose. Crypto, units, dates, and time zones are outside this module; upstream's calculator remains responsible for its existing answers.

The switch stays hidden: `LauncherScreen` synchronously calls `CalcMemo.evaluate` and routes calculator actions through its existing coordinator. An async answer needs state and refresh ownership beyond the permitted two one-line hooks. This change adds no view or upstream hook. The visible real-app proof gate therefore does not apply.
