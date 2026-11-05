# OpenBot Agents

## Invariants

- The visible switch defaults off and removes Refresh OpenBot Agents when disabled. No island page or view is installed.
- Only HTTP URLs with the literal host 127.0.0.1 and an explicit port are accepted. Redirects are refused and no Origin header is sent.
- Credentials are read afresh on every request, including one retry after 401. Nothing is persisted or logged; errors contain fixed reasons rather than response bodies or credentials.
- A private ephemeral session has no URL cache or cookie store. Tests inject a fake transport and never access an OpenBot installation.
- Stop cancels refresh work, clears state and rejects late publications. Polling defaults inactive.
- Start is idempotent. Only an agents-list failure clears the list; pending failures are recorded by agent ID in pendingFailures and excluded from the waiting count. Cancellation aborts the refresh.

## Locations and formats

The credential reader uses OPENBOT_AUTOMATION_DIR or the OpenBot automation folder under Application Support. It trims the url and token files; absent files mean OpenBot off or Local scripts off. Bot and routine identifiers are opaque strings. Pending summaries retain prompt question text and counts of prompts, approvals and browser takeovers without interpreting unverified item fields. Extra JSON fields are ignored; malformed JSON is an error. Unknown delivery statuses remain unknown and never imply completion.

## Consumer API

NotchcastCore.openBotAgents refreshes on module start and through its gated command, which reports the number of bots with waiting items through the neutral upstream message HUD. setActive(true) enables thirty-second polling for a future visible consumer; setActive(false) returns to one refresh without a timer.

OpenBotService exposes agents(), pending(agent:), send(agent:text:) and delivery(agent:id:). Sending returns the 202 receipt; callers follow its delivery identifiers with delivery(agent:id:) until a terminal status. Each send creates a fresh clientMessageId UUID and refuses encoded JSON bodies over 32768 bytes before reading credentials or using transport. Transport errors and HTTP failures have distinct typed states. Message and delivery calls belong to their caller's structured task and cancellation; the module owns refresh work only.

Answering prompts and approvals is out of scope because the answer and decision schemas are not verified. No routine execution API is implemented. OpenBot uses PolyForm Noncommercial: this implementation uses its API contract only and copies no OpenBot code. The Codync host is not built: it is not installed and its API is not stable.

Missing or null routines and prompt questions default to empty arrays; question text is optional. Missing pending collections default to empty arrays. Delivery answers retain only string values; other shapes become nil. Non-JSON and incorrect top-level response types are malformed. These tolerant fields do not claim verification of the pending-item or answer schemas.

## Verification

Tests/nc-OpenBotAgents-engine-test.swift uses synthetic in-memory fixtures for bots, pending questions, message receipts, delivery states, HTTP failures, credential rotation, URL restrictions, size limits and stop cancellation. No real OpenBot calls or automation-folder reads are part of verification. App compilation and live integration remain for the landing lane.
