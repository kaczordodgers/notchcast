import Foundation

enum AgentThreadParser {
    private struct Row: Decodable {
        let threadId: String
        let title: String?
        let projectId: String?
        let model: String?
        let status: String?
        let link: URL
        let updatedAt: String
        let settled: Bool?
    }

    private struct Show: Decodable {
        struct Detail: Decodable { let status: String?; let pendingRequestCount: Int }
        let thread: Detail
    }

    enum Failure: Error { case invalidData }

    static func list(_ data: Data, project: String = "") throws -> [AgentThread] {
        let decoder = JSONDecoder()
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let rows: [Any]
        if let array = value as? [Any] {
            rows = array
        } else if let envelope = value as? [String: Any], let array = envelope["threads"] as? [Any] {
            rows = array
        } else {
            throw Failure.invalidData
        }
        var ids = Set<String>()
        return rows.compactMap { value in
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let row = try? decoder.decode(Row.self, from: data),
                  !row.threadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validLink(row.link),
                  let date = ISO8601DateFormatter().date(from: row.updatedAt)
                    ?? fractionalDate(row.updatedAt),
                  ids.insert(row.threadId).inserted else { return nil }
            return AgentThread(id: row.threadId, title: row.title ?? "", project: project,
                               model: row.model ?? "", phase: phase(row.status), pendingCount: 0,
                               link: row.link, updatedAt: date, settled: row.settled ?? false)
        }
    }

    static func show(_ data: Data, updating thread: AgentThread) throws -> AgentThread {
        let detail = try JSONDecoder().decode(Show.self, from: data).thread
        guard detail.pendingRequestCount >= 0 else { throw Failure.invalidData }
        var updated = thread
        updated.pendingCount = detail.pendingRequestCount
        updated.phase = phase(detail.status, pendingCount: updated.pendingCount)
        return updated
    }

    static func select(_ threads: [AgentThread], now: Date) -> [AgentThread] {
        threads.filter {
            $0.phase.waiting || (!$0.settled && !$0.phase.finished)
                || now.timeIntervalSince($0.updatedAt) <= 30 * 60
        }.sorted {
            if $0.phase.waiting != $1.phase.waiting { return $0.phase.waiting }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    static func phase(_ status: String?, pendingCount: Int = 0) -> AgentThread.Phase {
        switch status ?? "idle" {
        case "preparing", "queued", "starting": .starting
        case "running": .running
        case "waiting": pendingCount > 0 ? .waitingForApproval : .waitingForInput
        case "completed": .completed
        case "failed", "interrupted", "cancelled", "rolled_back": .failed
        default: .stale
        }
    }

    private static func validLink(_ link: URL) -> Bool {
        switch link.scheme?.lowercased() {
        case "https": link.host?.isEmpty == false
        case "t3-thread": true
        case "http": ["127.0.0.1", "localhost"].contains(link.host?.lowercased() ?? "")
        default: false
        }
    }

    private static func fractionalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
