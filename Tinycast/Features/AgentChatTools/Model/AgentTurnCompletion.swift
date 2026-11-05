import Foundation

struct AgentTurnCompletion: Sendable {
    static let rule = """
        Keep taking concrete steps until the task is complete. Before finishing, verify every requested
        deliverable exists or succeeded, then give the final answer. If blocked, state plainly what
        prevents progress. Otherwise take the most useful next step. Never end with only a promise
        to act, and never repeat a tool call already completed.
        """
    static let continuation = "Continue: finish the task, or say plainly what blocks you."
    var enabled: Bool
    private var continued = false

    static func isUnfinished(_ text: String) -> Bool {
        let segments = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).last ?? ""
        return segments.range(
            of: "(?:^|[.!?]\\s+)(?:Now\\s+)?(?:Let me|I['’]ll|I will)\\s+(?:now\\s+)?"
                + "(?:check|verify|inspect|read|open|search|look|run|test|fix|write|continue)\\b[^.!?]*[.!?]?$",
            options: [.regularExpression, .caseInsensitive]) != nil
            && segments.range(of: "\\b(?:once|if|when|after) you\\b",
                options: [.regularExpression, .caseInsensitive]) == nil
    }

    func preparing(_ request: AIRequest) -> AIRequest {
        guard enabled else { return request }
        return AIRequest(
            instructions: [request.instructions, Self.rule].compactMap { $0 }.joined(separator: "\n\n"),
            messages: request.messages, maxOutputTokens: request.maxOutputTokens,
            webSearch: request.webSearch, tools: request.tools, conversationID: request.conversationID)
    }

    mutating func resume(text: String, responseItems: [JSONValue], messages: inout [AIMessage]) -> Bool {
        guard enabled, !continued, Self.isUnfinished(text) else { return false }
        continued = true
        messages.append(AIMessage(role: .assistant, text: text, responseItems: responseItems))
        messages.append(AIMessage(role: .user, text: Self.continuation))
        return true
    }
}
