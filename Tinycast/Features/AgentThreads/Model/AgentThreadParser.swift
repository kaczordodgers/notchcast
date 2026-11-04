import Foundation

enum AgentThreadParser {
    private struct Row: Decodable {
        let threadId: String
        let title: String?
        let project: String?
        let model: String?
        let status: String
        let link: URL
        let updatedAt: String
        let settled: Bool?
    }

    private struct List: Decodable { let threads: [Row] }
    private struct Show: Decodable {
        struct Detail: Decodable { let status: String; let pendingRequestCount: Int }
        let thread: Detail
    }

    enum Failure: Error { case invalidData }

    static func list(_ data: Data) throws -> [AgentThread] {
        let decoder = JSONDecoder()
        let rows: [Row]
        if let array = try? decoder.decode([Row].self, from: data) {
            rows = array
        } else {
            rows = try decoder.decode(List.self, from: data).threads
        }
        var ids = Set<String>()
        return try rows.map { row in
            guard !row.threadId.isEmpty, ids.insert(row.threadId).inserted,
                  ["t3", "https"].contains(row.link.scheme?.lowercased() ?? ""),
                  let date = ISO8601DateFormatter().date(from: row.updatedAt)
                    ?? fractionalDate(row.updatedAt) else { throw Failure.invalidData }
            return AgentThread(id: row.threadId, title: row.title ?? "", project: row.project ?? "",
                               model: row.model ?? "", phase: phase(row.status), pendingCount: 0,
                               link: row.link, updatedAt: date, settled: row.settled ?? false)
        }
    }

    static func show(_ data: Data, updating thread: AgentThread) throws -> AgentThread {
        let detail = try JSONDecoder().decode(Show.self, from: data).thread
        guard detail.pendingRequestCount >= 0 else { throw Failure.invalidData }
        var updated = thread
        updated.pendingCount = detail.pendingRequestCount
        updated.phase = phase(detail.status)
        if updated.pendingCount > 0, !updated.phase.waiting { updated.phase = .waitingForApproval }
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

    static func phase(_ status: String) -> AgentThread.Phase {
        AgentThread.Phase(rawValue: status) ?? .stale
    }

    private static func fractionalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
