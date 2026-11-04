import Foundation

// Adapted from CodyncKit at 1055636; provenance and licence are in SOURCE-NOTICE.md.
struct CodyncHostClient: BotHostClient {
    let transport: BotHostTransport

    private struct Snapshot: Decodable, Sendable {
        let bots: [Bot]
        let entries: [Entry]
        struct Bot: Decodable, Sendable { let id: String; let name: String; let status: String }
    }

    private struct Entry: Decodable, Sendable {
        let id: String
        let botId: String
        let kind: String
        let data: Content
        struct Content: Decodable, Sendable {
            let text: String?
            let status: String?
            let options: [Option]?
        }
        struct Option: Decodable, Sendable { let optionId: String }
    }

    private struct Sent: Decodable, Sendable { let entry: Entry }
    private struct Empty: Decodable, Sendable {}

    private func call<T: Decodable & Sendable>(_ method: String, _ body: [String: String]) async throws -> T {
        try await transport.call(path: ["api", method], body: JSONEncoder().encode(body), as: T.self)
    }

    private func snapshot() async throws -> Snapshot {
        try await transport.call(path: ["api", "sync"], body: Data("{\"since\":0}".utf8), as: Snapshot.self)
    }

    func list() async throws -> [BotHostBot] {
        try await snapshot().bots.filter { BotHostAccess.allows($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }

    func message(botID: String, text: String) async throws -> BotHostState {
        try BotHostAccess.validate(botID)
        do {
            let _: Sent = try await call("send", ["botId": botID, "text": text, "clientNonce": UUID().uuidString])
            return .done
        } catch BotHostTransport.Failure.timedOut { return .timedOut } catch
        BotHostTransport.Failure.unreachable { return .unreachable }
    }

    func status(botID: String) async throws -> BotHostState {
        try BotHostAccess.validate(botID)
        do {
            guard let bot = try await snapshot().bots.first(where: { $0.id == botID }) else {
                throw BotHostTransport.Failure.invalidResponse
            }
            switch bot.status {
            case "idle": return .done
            case "working": return .working
            case "needsInput": return .waitingForPerson
            case "error": return .failed
            default: throw BotHostTransport.Failure.invalidResponse
            }
        } catch BotHostTransport.Failure.timedOut { return .timedOut } catch
        BotHostTransport.Failure.unreachable { return .unreachable }
    }

    func pending(botID: String) async throws -> [BotHostPending] {
        try BotHostAccess.validate(botID)
        return try await snapshot().entries.filter {
            $0.botId == botID && $0.kind == "permission" && $0.data.status == "pending"
        }.map { .init(id: $0.id, text: $0.data.text ?? "", options: $0.data.options?.map(\.optionId) ?? []) }
    }

    func answer(botID: String, requestID: String, text: String) async throws -> BotHostState {
        try await message(botID: botID, text: text)
    }

    func approve(botID: String, requestID: String, optionID: String) async throws -> BotHostState {
        try BotHostAccess.validate(botID)
        guard try await pending(botID: botID).contains(where: {
            $0.id == requestID && $0.options.contains(optionID)
        }) else { throw BotHostTransport.Failure.rejected }
        do {
            let _: Empty = try await call("respondPermission", ["entryId": requestID, "optionId": optionID])
            return .done
        } catch BotHostTransport.Failure.timedOut { return .timedOut } catch
        BotHostTransport.Failure.unreachable { return .unreachable }
    }
}
