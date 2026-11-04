import Foundation

struct OpenBotAgent: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let routines: [Routine]

    struct Routine: Decodable, Sendable, Equatable {
        let id: String
        let name: String
        let active: Bool
    }
}

struct OpenBotPending: Decodable, Sendable, Equatable {
    struct Prompt: Decodable, Sendable, Equatable {
        struct Question: Decodable, Sendable, Equatable {
            let question: String
        }
        let questions: [Question]
    }
    struct Item: Decodable, Sendable, Equatable {}
    let prompts: [Prompt]
    let approvals: [Item]
    let browserTakeovers: [Item]
    var isWaiting: Bool { !prompts.isEmpty || !approvals.isEmpty || !browserTakeovers.isEmpty }
}

struct OpenBotDelivery: Decodable, Sendable, Equatable {
    enum Status: String, Decodable, Sendable {
        case queued, pending, running, completed, failed, interrupted, cancelled, unknown

        init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        var hasEnded: Bool { [.completed, .failed, .interrupted, .cancelled].contains(self) }
    }
    let id: String
    let status: Status
    let recipientAgentId: String?
    let turnId: String?
    let error: String?
    let answer: String?
}

struct OpenBotReceipt: Decodable, Sendable {
    let messageId: String
    let deliveries: [OpenBotDelivery]
}

enum OpenBotFailure: Error, Sendable, Equatable {
    case off, invalidURL, unreachable, unauthorized, forbidden, missing, rateLimited, server
    case input, method, conflict, oversized, mediaType, unexpected, malformed
}
