import Foundation

/// Raw values are the wire names; a Mac on an older build still sends them.
enum MachLinkMethod: String, CaseIterable, Sendable {
    case aiUsage = "ai-usage"
    case agentThreads = "agent-threads"
    case dialogs
    case mbpFans = "mbp-fans"
    case remoteScreenAvailability = "remote-screen-availability"
    case linkHealth = "link-health"
    case shelfItem = "shelf-item"
    case todoSync = "todo-sync"
}

struct MachLinkMessage: Codable, Sendable, Equatable {
    static let maximumBytes = 65_536

    let version: Int
    let id: UUID
    let method: String
    let payload: Data

    init<Value: Encodable>(id: UUID = UUID(), method: String, value: Value) throws {
        version = 1
        self.id = id
        self.method = method
        payload = try JSONEncoder().encode(value)
    }

    func value<Value: Decodable>(as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: payload)
    }

    func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let message = try JSONDecoder().decode(Self.self, from: data)
        guard message.version == 1 else { throw Failure.invalidMessage }
        return message
    }

    enum Failure: Error {
        case tooLarge, invalidMessage, disconnected, timedOut, invalidPairing
    }
}
