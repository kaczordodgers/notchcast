# Build stats snapshot schema

Version 1 is a generic local JSON contract between a separate collector and a future viewer.
There is no collector, file-path preference or viewer in this contract. Publish snapshots atomically.
Keep private snapshots outside the repository; sanitize all labels and summaries before export.
Never include project, person or client names, external task/thread identifiers, paths or secrets.

All fields are required. Empty arrays and an empty metrics object are valid.

| Field | Type | Meaning |
| --- | --- | --- |
| schemaVersion | integer | Exactly `1`; unsupported versions throw `unsupportedVersion` |
| tokens | array | Unique model/effort pairs; aggregate counts over the snapshot's scope |
| tokens[].model | string | Generic model label |
| tokens[].effort | string | Generic effort label; open vocabulary |
| tokens[].inputTokens | integer | Nonnegative signed 64-bit input token count |
| tokens[].outputTokens | integer | Nonnegative signed 64-bit output token count |
| timeline | array | Milestones in ascending date order |
| changelog | array | Developer changes in ascending date order |
| timeline[] / changelog[].date | string | Real Gregorian UTC calendar day, exactly `YYYY-MM-DD` |
| timeline[] / changelog[].summary | string | Generic description |
| qualityMetrics | object | Generic metric names mapped to finite, nonnegative numbers |

Dates may repeat; ordering is checked separately in each array. Counts are independent aggregates;
no totals are inferred or summed. Metric names define their unit (for example `coveragePercent`);
the contract imposes no percentage range. Text cannot be blank after trimming whitespace.
Labels and metric names allow at most 80 UTF-8 bytes; summaries allow 2,000.
Each array allows at most 1,000 entries; metrics allow at most 100 keys.
`BuildStatsSnapshot.decode(_:)` rejects input above 1 MiB before JSON parsing. Consumers must use
that entry point and bound file reads to the same limit. Direct Codable decoding also validates
values, collection sizes and dates, but cannot enforce the original byte size.
Malformed or missing fields throw `DecodingError`; semantic failures throw
`BuildStatsSnapshot.ValidationError`. Unknown JSON keys are ignored for additive metadata;
breaking changes require a new schema version. Privacy is the collector's responsibility:
validation checks structure and bounds, not whether free text identifies someone.

Example (also shipped as the synthetic `Tests/fixtures/build-stats-v1.json` fixture):

```json
{
  "schemaVersion": 1,
  "tokens": [
    {"model": "model-a", "effort": "standard", "inputTokens": 1200, "outputTokens": 300},
    {"model": "model-b", "effort": "high", "inputTokens": 800, "outputTokens": 200}
  ],
  "timeline": [
    {"date": "2026-01-01", "summary": "Initial prototype"},
    {"date": "2026-01-02", "summary": "Validation complete"}
  ],
  "changelog": [{"date": "2026-01-02", "summary": "Added snapshot validation"}],
  "qualityMetrics": {"checksPassed": 12, "coveragePercent": 85.5}
}
```
