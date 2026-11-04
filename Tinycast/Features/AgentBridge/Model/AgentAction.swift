import Foundation

struct AgentAction: Sendable {
    enum Danger: String, Codable, Sendable { case harmless, consent, dangerous }

    let id: String
    let title: String
    var parameters = AgentParameterSchema()
    var danger = Danger.consent

    func json(available: Bool) -> AgentJSON {
        .object([
            "id": .string(id), "title": .string(title), "parameters": parameters.json,
            "danger": .string(danger.rawValue), "available": .bool(available)
        ])
    }
}
