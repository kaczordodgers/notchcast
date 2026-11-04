# Agent pricing

Pure API-value estimates from synthetic or adapter-supplied usage. No log or network access.
The bundled standard-rate USD table was reviewed 2026-10-30. It is data from
`vorssaint/vorssaint-utils/Resources/agent-prices.json` (GPL-3.0-or-later),
Copyright (C) 2026 Vorssaint; vendor sources are the Claude and OpenAI pricing pages.
Implementation is independent. This table estimates base token value, excluding fast-tier,
long-context, one-hour cache, regional and tool-call premiums. It is not an invoice.

The lead owns shared registration outside this worker's permitted folder:

- Add `agentPricing` to `NotchcastFeature`, default off, needsIsland false, no grants.
- Title: Agent API Value. Subtitle: Estimate API value from local agent token usage.
- Add those strings in all eight locales and include the feature in settings search.
- Conform `AgentPricingModule` to `NotchcastModule`; create it using the throwing
  `AgentPricingCatalog.bundled()` factory and report decoding failure through the existing HUD.
- Append `.init(requires: [.agentPricing], module: pricing),` to the core module list.
- Feed complete snapshots through `update`; `stop` clears visible usage and budget state.

Adapters conform to `AgentTokenUsage`. Each record represents a disjoint token increment;
input excludes both cache categories. Exact model identifiers are required. Unknown models
remain unpriced unless the adapter supplies an OpenCode-reported USD cost. Totals track
unpriced records so partial estimates cannot be mistaken for complete spend.
Calendar and current time are injected. Round only the final displayed total, half up to cents.
Daily budget notifications fire once per local day while enabled; the lead supplies the budget
and routes the callback through the existing notice presenter. No new commands are required.

Live integration, switch visibility and notifications are not verified (morning).
