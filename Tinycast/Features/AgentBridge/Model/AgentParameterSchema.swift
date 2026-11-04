import Foundation

struct AgentParameterSchema: Sendable {
    struct Property: Sendable {
        enum Kind: String, Sendable { case string, number, integer, boolean }
        let kind: Kind
        var minimum: Double?
        var maximum: Double?
        var allowedValues: [AgentJSON]?
        var minimumLength: Int?
        var secret = false

        func accepts(_ value: AgentJSON) -> Bool {
            guard allowedValues.map({ $0.contains(value) }) ?? true else { return false }
            return switch (kind, value) {
            case (.string, .string(let text)): minimumLength.map { text.count >= $0 } ?? true
            case (.boolean, .bool): true
            case (.number, .number(let number)), (.integer, .number(let number)):
                number.isFinite && (kind != .integer || number.rounded() == number)
                    && (minimum.map { number >= $0 } ?? true)
                    && (maximum.map { number <= $0 } ?? true)
            default: false
            }
        }

        var json: AgentJSON {
            var fields: [String: AgentJSON] = ["type": .string(kind.rawValue)]
            if let minimum { fields["minimum"] = .number(minimum) }
            if let maximum { fields["maximum"] = .number(maximum) }
            if let allowedValues { fields["enum"] = .array(allowedValues) }
            if let minimumLength { fields["minLength"] = .number(Double(minimumLength)) }
            if secret { fields["secret"] = .bool(true) }
            return .object(fields)
        }
    }

    var properties: [String: Property] = [:]
    var required: Set<String> = []

    func accepts(_ value: AgentJSON) -> Bool {
        guard case .object(let fields) = value,
            required.isSubset(of: fields.keys), required.isSubset(of: properties.keys)
        else { return false }
        return fields.allSatisfy { properties[$0.key]?.accepts($0.value) == true }
    }

    var json: AgentJSON {
        .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object(properties.mapValues(\.json)),
            "required": .array(required.sorted().map(AgentJSON.string))
        ])
    }
}
