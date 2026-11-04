import Foundation

// This wire contract is assumed from the catalogue, pending verification against application code.
struct OpenBotBridge: BotHostClient {
    let transport: BotHostTransport

    private struct Request: Encodable {
        var botId: String?
        var text: String?
        var requestId: String?
        var optionId: String?
    }

    private struct Response: Decodable, Sendable {
        let exitCode: Int
        var bots: [Bot]?
        var pending: [Pending]?

        struct Bot: Decodable, Sendable { let id: String; let name: String }
        struct Pending: Decodable, Sendable { let id: String; let text: String; let options: [String] }
    }

    private func call(_ operation: String, _ request: Request) async throws -> Response {
        if let id = request.botId { try BotHostAccess.validate(id) }
        let response = try await transport.call(
            path: ["api", operation], body: JSONEncoder().encode(request), as: Response.self)
        return response
    }

    func list() async throws -> [BotHostBot] {
        let response = try await call("list", Request())
        guard response.exitCode == 0, let bots = response.bots else {
            throw BotHostTransport.Failure.invalidResponse
        }
        return bots.filter { BotHostAccess.allows($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }

    func message(botID: String, text: String) async throws -> BotHostState {
        try await state("message", Request(botId: botID, text: text))
    }

    func status(botID: String) async throws -> BotHostState {
        try await state("status", Request(botId: botID))
    }

    func pending(botID: String) async throws -> [BotHostPending] {
        let response = try await call("pending", Request(botId: botID))
        guard [0, 3].contains(response.exitCode), let pending = response.pending else {
            throw BotHostTransport.Failure.invalidResponse
        }
        return pending.map { .init(id: $0.id, text: $0.text, options: $0.options) }
    }

    func answer(botID: String, requestID: String, text: String) async throws -> BotHostState {
        try await state("answer", Request(botId: botID, text: text, requestId: requestID))
    }

    func approve(botID: String, requestID: String, optionID: String) async throws -> BotHostState {
        try await state("approve", Request(botId: botID, requestId: requestID, optionId: optionID))
    }

    private func state(_ operation: String, _ request: Request) async throws -> BotHostState {
        do { return BotHostState(exitCode: try await call(operation, request).exitCode) } catch
        BotHostTransport.Failure.timedOut { return .timedOut } catch
        BotHostTransport.Failure.unreachable { return .unreachable }
    }
}
