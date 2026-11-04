import Foundation

protocol BotHostClient: Sendable {
    func list() async throws -> [BotHostBot]
    func message(botID: String, text: String) async throws -> BotHostState
    func status(botID: String) async throws -> BotHostState
    func pending(botID: String) async throws -> [BotHostPending]
    func answer(botID: String, requestID: String, text: String) async throws -> BotHostState
    func approve(botID: String, requestID: String, optionID: String) async throws -> BotHostState
}

struct BotHostBot: Sendable, Equatable {
    let id: String
    let name: String
}

struct BotHostPending: Sendable, Equatable {
    let id: String
    let text: String
    let options: [String]
}

enum BotHostAccess {
    static func validate(_ id: String) throws {
        guard !id.isEmpty, !id.components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .contains("agent-2784f2ac") else { throw BotHostTransport.Failure.rejected }
    }

    static func allows(_ id: String) -> Bool { (try? validate(id)) != nil }
}
