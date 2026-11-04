import Foundation
import CoreFoundation

struct AgentSessionAccumulator: Sendable {
    private(set) var session: AgentSession
    private var recentUsage: [String: AgentSession.Tokens] = [:]
    private var recentOrder: [String] = []
    private var totals: [String: AgentSession.Tokens] = [:]
    private var codexHeaderRead = false
    private var explicitCodexUsage = false
    private var copilotFinalResponse = false
    private let calendar: Calendar

    init(provider: AgentSession.Provider, id: String, calendar: Calendar) {
        session = AgentSession(id: id, provider: provider)
        self.calendar = calendar
    }

    mutating func consume(_ line: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = json["type"] as? String else { return false }
        let date = Self.date(json["timestamp"])
        switch session.provider {
        case .claude: claude(json, type: type, date: date)
        case .codex: codex(json, type: type, date: date)
        case .copilot: copilot(json, type: type, date: date)
        case .opencode: break
        }
        return true
    }

    mutating func activity(at date: Date?, ended: Bool = false) {
        guard let date else { return }
        session.startedAt = min(session.startedAt ?? date, date)
        if date >= session.lastActivityAt ?? .distantPast {
            session.lastActivityAt = date
            session.endedAt = ended ? date : nil
        }
    }

    mutating func context(project: String?, model: String?) {
        if let project, !project.isEmpty { session.project = project }
        if let model, !model.isEmpty { session.model = model }
    }

    mutating func addUsage(_ tokens: AgentSession.Tokens, model: String?, at date: Date?,
                           key: String? = nil, cumulative: Bool = false, cost: Double? = nil) {
        guard let date else { return }
        let name = model ?? session.model
        var added = tokens
        if cumulative {
            let previous = totals[key ?? name ?? ""] ?? .init()
            added = tokens.growth(after: previous)
            totals[key ?? name ?? ""] = previous + added
        } else if let key {
            let previous = recentUsage[key] ?? .init()
            added = tokens.growth(after: previous)
            if recentUsage[key] == nil { recentOrder.append(key) }
            recentUsage[key] = previous + added
            if recentOrder.count > 256 { recentUsage[recentOrder.removeFirst()] = nil }
        }
        guard added != .init() || cost != nil else { return }
        let day = calendar.startOfDay(for: date)
        if let index = session.usage.firstIndex(where: { $0.model == name && $0.day == day }) {
            session.usage[index].tokens += added
            if let cost { session.usage[index].reportedCost = (session.usage[index].reportedCost ?? 0) + cost }
        } else {
            session.usage.append(.init(model: name, day: day, tokens: added, reportedCost: cost))
        }
    }

    private mutating func claude(_ json: [String: Any], type: String, date: Date?) {
        guard type == "user" || type == "assistant" else { return }
        if let id = json["sessionId"] as? String { session.id = "claude:" + id }
        context(project: json["cwd"] as? String, model: nil)
        let message = json["message"] as? [String: Any] ?? [:]
        let stop = message["stop_reason"] as? String
        activity(at: date, ended: ["end_turn", "stop_sequence", "max_tokens", "refusal"].contains(stop ?? ""))
        guard type == "assistant" else { return }
        context(project: nil, model: message["model"] as? String)
        guard let usage = message["usage"] as? [String: Any] else { return }
        let tokens = AgentSession.Tokens(
            input: Self.count(usage["input_tokens"]), cacheRead: Self.count(usage["cache_read_input_tokens"]),
            cacheWrite: Self.count(usage["cache_creation_input_tokens"]), output: Self.count(usage["output_tokens"]),
            reasoning: Self.count((usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"]))
        addUsage(tokens, model: session.model, at: date, key: message["id"] as? String)
    }

    private mutating func codex(_ json: [String: Any], type: String, date: Date?) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        switch type {
        case "session_meta":
            guard !codexHeaderRead else { return }
            codexHeaderRead = true
            if let id = payload["id"] as? String { session.id = "codex:" + id }
            context(project: payload["cwd"] as? String, model: nil)
            activity(at: date)
        case "turn_context":
            context(project: payload["cwd"] as? String, model: payload["model"] as? String)
        case "token_usage_record":
            guard let usage = payload["usage"] as? [String: Any] else { return }
            explicitCodexUsage = true
            activity(at: date)
            addUsage(Self.codexTokens(usage), model: session.model, at: date, key: payload["response_id"] as? String)
        case "event_msg":
            let event = payload["type"] as? String ?? ""
            guard ["task_started", "task_complete", "turn_aborted", "token_count"].contains(event) else { return }
            if event != "token_count" {
                activity(at: date, ended: event == "task_complete" || event == "turn_aborted")
            }
            guard event == "token_count", !explicitCodexUsage,
                  let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any] else { return }
            let tokens = Self.codexTokens(usage)
            let growth = tokens.growth(after: totals["codex-total"] ?? .init())
            addUsage(tokens, model: session.model, at: date, key: "codex-total", cumulative: true)
            if growth != .init() { activity(at: date) }
        default: break
        }
    }

    private mutating func copilot(_ json: [String: Any], type: String, date: Date?) {
        guard json["agentId"] == nil, let data = json["data"] as? [String: Any] else { return }
        switch type {
        case "session.start":
            if let id = data["sessionId"] as? String { session.id = "copilot:" + id }
            let context = data["context"] as? [String: Any] ?? [:]
            self.context(project: context["cwd"] as? String, model: data["selectedModel"] as? String)
        case "session.context_changed":
            context(project: data["gitRoot"] as? String ?? data["cwd"] as? String, model: nil)
        case "session.model_change": context(project: nil, model: data["newModel"] as? String)
        case "user.message", "assistant.turn_start":
            copilotFinalResponse = false
            context(project: nil, model: data["model"] as? String)
        case "assistant.message":
            context(project: nil, model: data["model"] as? String)
            copilotFinalResponse = (data["toolRequests"] as? [Any] ?? []).isEmpty
                && !["thinking", "commentary"].contains(data["phase"] as? String ?? "")
        case "assistant.turn_end":
            guard copilotFinalResponse else { return }
            copilotFinalResponse = false
            activity(at: date, ended: true)
            return
        case "abort":
            activity(at: date, ended: true)
            return
        case "session.shutdown":
            for (model, value) in data["modelMetrics"] as? [String: Any] ?? [:] {
                guard let metric = value as? [String: Any] else { continue }
                let usage = metric["usage"] as? [String: Any] ?? [:]
                let details = metric["tokenDetails"] as? [String: Any] ?? [:]
                func count(_ key: String, _ fallback: String) -> Int64 {
                    Self.count((details[key] as? [String: Any])?["tokenCount"] ?? usage[fallback])
                }
                addUsage(.init(input: count("input", "inputTokens"), cacheRead: count("cache_read", "cacheReadTokens"),
                               cacheWrite: count("cache_write", "cacheWriteTokens"), output: count("output", "outputTokens"),
                               reasoning: Self.count(usage["reasoningTokens"])), model: model, at: date, cumulative: true)
            }
            activity(at: date, ended: true)
            return
        default: return
        }
        activity(at: date)
    }

    private static func codexTokens(_ usage: [String: Any]) -> AgentSession.Tokens {
        let cached = count(usage["cached_input_tokens"])
        return .init(input: max(0, count(usage["input_tokens"]) - cached), cacheRead: cached,
                     output: count(usage["output_tokens"]), reasoning: count(usage["reasoning_output_tokens"]))
    }

    static func count(_ value: Any?) -> Int64 {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value < Double(Int64.max), value.rounded(.towardZero) == value else { return 0 }
        return Int64(value)
    }

    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let value = number.doubleValue
            guard value.isFinite, value >= 0, value < 253_402_300_800_000 else { return nil }
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        guard let text = value as? String else { return nil }
        let fractional = Date.ISO8601FormatStyle().year().month().day()
            .time(includingFractionalSeconds: true).timeZone(separator: .colon)
        return (try? Date(text, strategy: fractional)) ?? (try? Date(text, strategy: .iso8601))
    }
}
