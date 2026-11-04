import Foundation

struct T3Thread: Decodable, Identifiable, Sendable {
    let threadId: String
    var id: String { threadId }
    let title: String?
    let status: String?
    let model: String?
    let providerInstanceId: String?
    let project: Project?
    let settled: Bool?
    let snoozed: Bool?
    let link: String?
    let updatedAt: String?
    let pendingRequestCount: Int?

    enum Project: Decodable, Sendable {
        case name(String)
        case details(id: String?, title: String?, path: String?)

        private enum CodingKeys: String, CodingKey { case id, title, path }

        init(from decoder: any Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                self = .name(name)
                return
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self = .details(id: try values.decodeIfPresent(String.self, forKey: .id),
                            title: try values.decodeIfPresent(String.self, forKey: .title),
                            path: try values.decodeIfPresent(String.self, forKey: .path))
        }
    }

    enum Phase: String, Sendable {
        case starting, running, waiting_for_approval, waiting_for_input, completed, failed, stale
    }

    var phase: Phase {
        switch status {
        case "queued", "preparing", "starting": .starting
        case "running": .running
        case "waiting", "waiting_for_input": .waiting_for_input
        case "waiting_for_approval": .waiting_for_approval
        case "completed": .completed
        case "failed", "cancelled", "interrupted": .failed
        default: .stale
        }
    }

    var updatedDate: Date? {
        guard let updatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: updatedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: updatedAt)
    }
}
