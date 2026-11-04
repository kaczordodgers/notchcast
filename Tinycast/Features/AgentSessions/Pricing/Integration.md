# Agent pricing

Pure API-value estimates from synthetic or adapter-supplied usage. No log or network access.
The bundled standard-rate USD table was reviewed 2026-10-30. It is data from
`vorssaint/vorssaint-utils/Resources/agent-prices.json` (GPL-3.0-or-later),
Copyright (C) 2026 Vorssaint; vendor sources are the Claude and OpenAI pricing pages.
Implementation is independent. This table estimates base token value, excluding fast-tier,
long-context, one-hour cache, regional and tool-call premiums. It is not an invoice.

The sessions module publishes `pricingReport` from the index's per-model, per-day usage.
Agent API Value defaults off under Agent Session Logs; disabling its parent stops scanning
and clears both snapshots. Refresh Agent Session Logs is gated by the parent switch.
Adapters conform to `AgentTokenUsage`. Each record represents a disjoint token increment;
input excludes both cache categories. A trailing eight-digit model date is normalized. Unknown models
remain unpriced unless the adapter supplies an OpenCode-reported USD cost. Totals track
unpriced records so partial estimates cannot be mistaken for complete spend.
The injected calendar defines usage days during indexing and pricing. Round only the final
displayed total, half up to cents. The bundled engine is decoded once per process.

Live switch visibility is not verified (morning).
