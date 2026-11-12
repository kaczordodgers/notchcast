import Foundation

struct OpenBotAgent: Decodable, Sendable, Equatable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(String.self, forKey: .id)) ?? ""
        name = (try? values.decode(String.self, forKey: .name)) ?? ""
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

enum OpenBotFailure: Error, Sendable, Equatable {
    case off, invalidURL, unreachable, unauthorized, forbidden, missing, rateLimited, server
    case input, method, conflict, oversized, mediaType, unexpected, malformed
}
