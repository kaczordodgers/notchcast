import Foundation

// Reduced CodyncKit event projection at 1055636; see SOURCE-NOTICE.md for attribution.
enum CodyncHostEvent: Sendable, Equatable {
    case hello(hostID: String, revision: Int64)
    case bot(id: String, status: String)
    case botDeleted(id: String, revision: Int64)
    case entry(id: String, botID: String)
    case resync
    case unknown

    static func parse(_ data: Data) -> Self? {
        struct Envelope: Decodable {
            let type: String
            let hostId: String?
            let rev: Int64?
            let bot: Bot?
            let entry: Entry?
            struct Bot: Decodable {
                let id: String
                let status: String?
                let deleted: Bool?
                let rev: Int64?
            }
            struct Entry: Decodable { let id: String; let botId: String }
        }
        guard let raw = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch raw.type {
        case "hello": return .hello(hostID: raw.hostId ?? "", revision: raw.rev ?? 0)
        case "resync": return .resync
        case "bot":
            guard let bot = raw.bot, BotHostAccess.allows(bot.id) else { return nil }
            if bot.deleted == true { return .botDeleted(id: bot.id, revision: bot.rev ?? 0) }
            guard let status = bot.status else { return nil }
            return .bot(id: bot.id, status: status)
        case "entry":
            guard let entry = raw.entry, BotHostAccess.allows(entry.botId) else { return nil }
            return .entry(id: entry.id, botID: entry.botId)
        default: return .unknown
        }
    }
}
