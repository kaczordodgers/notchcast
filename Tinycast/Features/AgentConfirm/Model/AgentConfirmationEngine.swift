import Foundation

struct AgentConfirmationEngine {
    struct Request: Equatable, Sendable {
        let id: UUID
        let agentID: String
        let client: String
        let actionID: String
        let parameters: [String: String]
        let deadline: Date
    }

    struct Pending: Sendable {
        let request: Request
        let danger: AgentConsentPolicy.Danger
    }

    enum Choice: Sendable { case allowOnce, alwaysAllow, deny }
    enum Verdict: Equatable, Sendable { case allowOnce, alwaysAllow, deny }

    struct Reply: Equatable, Sendable {
        let id: UUID
        let verdict: Verdict
    }

    private(set) var queue: [Pending] = []
    private var seen: Set<UUID> = []
    var current: Pending? { queue.first }

    mutating func receive(
        _ request: Request, danger: AgentConsentPolicy.Danger?, enabled: Bool, now: Date
    ) -> [Reply] {
        var replies = expire(now: now)
        guard seen.insert(request.id).inserted else {
            queue.removeAll { $0.request.id == request.id }
            replies.append(Reply(id: request.id, verdict: .deny))
            return replies
        }
        guard enabled, let danger, !request.agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.deadline.timeIntervalSince1970.isFinite, request.deadline > now,
              request.agentID.utf8.count <= 256, request.client.utf8.count <= 256,
              request.actionID.utf8.count <= 256, request.parameters.count <= 64,
              request.parameters.allSatisfy({ $0.key.utf8.count <= 256 && $0.value.utf8.count <= 4096 })
        else {
            replies.append(Reply(id: request.id, verdict: .deny))
            return replies
        }
        queue.append(Pending(request: request, danger: danger))
        return replies
    }

    mutating func decide(id: UUID, choice: Choice, enabled: Bool, now: Date) -> [Reply] {
        var replies = expire(now: now)
        guard let pending = current, pending.request.id == id else { return replies }
        queue.removeFirst()
        let verdict: Verdict
        switch choice {
        case .deny: verdict = .deny
        case .allowOnce: verdict = enabled ? .allowOnce : .deny
        case .alwaysAllow:
            verdict = enabled && pending.danger == .consent ? .alwaysAllow : .deny
        }
        replies.append(Reply(id: id, verdict: verdict))
        return replies
    }

    mutating func expire(now: Date) -> [Reply] {
        let expired = queue.filter { $0.request.deadline <= now }
        queue.removeAll { $0.request.deadline <= now }
        return expired.map { Reply(id: $0.request.id, verdict: .deny) }
    }

    mutating func denyAll() -> [Reply] {
        defer { queue.removeAll() }
        return queue.map { Reply(id: $0.request.id, verdict: .deny) }
    }
}
