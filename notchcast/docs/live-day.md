# Day data for island wiring

No service starts during initialization. AppCore owns the instances; the island coordinator starts
and stops them. `DayWeatherModule` and `DayMarketsModule` gate their stores behind the island and
feature switches; `setVisible(_:)` starts polling only while the Day page is shown. Their settings
share the Day section under Notchcast. Activity slots and island views are wired separately.

- `DayCalendarService(store:)`: inject a `CalendarStore`; the service only reads its access and
  never requests permission itself. `records(in:)` queries an arbitrary date interval directly
  through EventKit, including recurrence, and returns each visible event with its `EKEvent`. It is
  empty without granted access and skips cancelled, declined and excluded-calendar events. Observe
  `revision` to invalidate queries: it advances on EventKit changes once a query has run, and on
  every exclusion edit. Observe `store.access` for permission state. `setExcludedCalendars`
  persists fork-only exclusions; `excludedCalendarIDs` reads them. `stop()` releases the range
  reader and its change observer; the owner controls the injected store's lifecycle.
- `DayEvent.current(in:now:)` and `next(in:now:)` exclude all-day events; current ends are exclusive.
- `DayWeatherStore`: `cities(matching:)`, `select(_:)`, `start()`, `stop()`, `refresh()`;
  observe `place`, `forecast`, `fetchedAt`, `lastError`. `isStale(now:)` uses a 30-minute threshold.
  A selected city is required; no location permission is requested. Failed refreshes retain the last
  forecast. Selecting a city persists it without starting a stopped store. Successful responses are
  cached at Application Support/Notchcast/weather.json in release;
  other bundle identifiers receive separate directories. Open-Meteo attribution belongs in the UI.
- `DayMarketsStore`: `setSymbols(_:)`, `setVisible(_:)`, `refresh()`; observe `quotes` and `lastError`.
  Observe `failedSymbols` for individual failures; successful symbols still publish their quotes.
  Visibility owns the three-minute polling task; refreshes respect a 60-second minimum attempt gap.
  Changing symbols resets the gap and refreshes immediately while visible.
  Call `setVisible(false)` on teardown. The default symbols are USDPLN=X, ^GSPC and BTC-USD.
  `change24Hours` is percent change against a chart sample within one hour of the 24-hour reference,
  or nil when no such sample exists (including market closures).

Default preference stores use a bundle-identifier-specific fork suite. Both network stores also
accept injected storage for isolated testing. Their errors are data for the future coordinator's
HUD, not UI presented by the services. Weather and markets work without calendar access.
