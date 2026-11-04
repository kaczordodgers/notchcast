import Foundation

struct AgentAction: Sendable {
    enum Danger: String, Codable, Sendable { case harmless, consent, dangerous }

    let id: String
    let title: String
    var parameters = AgentParameterSchema()
    var danger = Danger.consent

    func confirmationMessage(parameters values: AgentJSON) -> String {
        let heading = "local-cli · \(id)"
        guard case .object(let fields) = values, !fields.isEmpty else { return heading }
        let lines = fields.keys.sorted().map { name in
            if parameters.properties[name]?.secret == true { return "\(name): •••" }
            var value: String
            if case .string(let text) = fields[name] {
                value = text
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                value = (try? encoder.encode(fields[name])).map { String(decoding: $0, as: UTF8.self) } ?? ""
            }
            value = value.split(whereSeparator: \.isNewline).joined(separator: " ")
            return "\(name): \(value.prefix(60))\(value.count > 60 ? "…" : "")"
        }
        return ([heading] + lines).joined(separator: "\n")
    }

    func json(available: Bool) -> AgentJSON {
        .object([
            "id": .string(id), "title": .string(title), "parameters": parameters.json,
            "danger": .string(danger.rawValue), "available": .bool(available)
        ])
    }
}
