import Foundation

struct OpenBotAgent: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let routines: [Routine]

    enum CodingKeys: String, CodingKey { case id, name, routines }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        name = (try? values.decode(String.self, forKey: .name)) ?? ""
        routines = (try? values.decode(OpenBotLossyArray<Routine>.self, forKey: .routines))?.elements ?? []
    }

    struct Routine: Decodable, Sendable, Equatable {
        let id: String
        let name: String
        let active: Bool
    }
}

struct OpenBotPending: Decodable, Sendable, Equatable {
    struct Prompt: Decodable, Sendable, Equatable {
        struct Question: Decodable, Sendable, Equatable {
            let question: String?
        }
        let questions: [Question]

        enum CodingKeys: String, CodingKey { case questions }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            questions = (try? values.decode(OpenBotLossyArray<Question>.self, forKey: .questions))?.elements ?? []
        }
    }
    struct Item: Decodable, Sendable, Equatable {
        private enum CodingKeys: CodingKey {}

        init(from decoder: any Decoder) throws {
            _ = try decoder.container(keyedBy: CodingKeys.self)
        }
    }
    let prompts: [Prompt]
    let approvals: [Item]
    let browserTakeovers: [Item]

    enum CodingKeys: String, CodingKey { case prompts, approvals, browserTakeovers }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        prompts = (try? values.decode(OpenBotLossyArray<Prompt>.self, forKey: .prompts))?.elements ?? []
        approvals = (try? values.decode(OpenBotLossyArray<Item>.self, forKey: .approvals))?.elements ?? []
        browserTakeovers = (try? values.decode(OpenBotLossyArray<Item>.self, forKey: .browserTakeovers))?.elements ?? []
    }
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

    enum CodingKeys: String, CodingKey { case id, status, recipientAgentId, turnId, error, answer }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        status = (try? values.decode(Status.self, forKey: .status)) ?? .unknown
        recipientAgentId = try? values.decode(String.self, forKey: .recipientAgentId)
        turnId = try? values.decode(String.self, forKey: .turnId)
        error = try? values.decode(String.self, forKey: .error)
        answer = try? values.decode(String.self, forKey: .answer)
    }
}

struct OpenBotReceipt: Decodable, Sendable {
    let messageId: String
    let deliveries: [OpenBotDelivery]
}

enum OpenBotFailure: Error, Sendable, Equatable {
    case off, invalidURL, unreachable, unauthorized, forbidden, missing, rateLimited, server
    case input, method, conflict, oversized, mediaType, unexpected, malformed
}
