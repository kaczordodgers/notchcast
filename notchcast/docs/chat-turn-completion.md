# Chat turn completion

When AI Chat Tools is running and the API chat offers tools, `AIChatCoordinator` enables `AgentTurnCompletion` in `AIToolLoopProvider`. Each request appends its model-facing completion rule to the existing instructions. The existing tool scope, consent checks and round/history limits still apply.

A tool-less reply ending in a first-person action announcement receives one model-facing user continuation per user turn. The loop preserves the assistant output items and accumulated tool results, then continues without invoking any previous call again. A second unfinished reply ends normally. Disabling AI Chat Tools retains upstream behavior. Installed CLI routes own their loops and are unaffected.

The rule and continuation are protocol instructions, never localized UI strings; no `String(localized:)` or string catalog changes are needed. The English heuristic intentionally recognizes only a narrow set of action announcements. `Tests/nc-AgentChatTools-completion-test.swift` checks detection, request history, the single retry bound and the disabled gate.
